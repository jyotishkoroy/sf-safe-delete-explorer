/**
 * Copyright 2026 Jyotishko Roy
 * Licensed under the Apache License, Version 2.0.
 */
public inherited sharing class SafeDeleteExplorerService {
    private static final Integer DEFAULT_MAX_COUNT_QUERIES = 70;
    private static final Integer ABSOLUTE_MAX_COUNT_QUERIES = 90;
    private static final Set<String> HIGH_RISK_OBJECTS = new Set<String>{
        'Attachment',
        'CombinedAttachment',
        'ContentDocumentLink',
        'ContentVersion',
        'EmailMessage',
        'Event',
        'FeedItem',
        'Note',
        'ProcessInstance',
        'ProcessInstanceStep',
        'ProcessInstanceWorkitem',
        'Task'
    };
    private static final Set<String> NOISE_SUFFIXES = new Set<String>{
        'ChangeEvent',
        'History',
        'OwnerSharingRule',
        'Share'
    };

    @AuraEnabled(cacheable=true)
    public static PreviewResponse preview(String recordId, Boolean showZeroCountRows, Integer maxCountQueries) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('A record Id is required.');
        }

        Id targetId;
        try {
            targetId = Id.valueOf(recordId.trim());
        } catch (Exception ex) {
            throw new AuraHandledException('The supplied record Id is not valid.');
        }

        Integer queryBudget = normalizeQueryBudget(maxCountQueries);
        Boolean includeZeroRows = showZeroCountRows == true;

        Schema.SObjectType parentType = targetId.getSObjectType();
        Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
        Map<String, SafeDeleteRule__mdt> ruleByChildObject = loadRules();

        PreviewResponse response = new PreviewResponse();
        response.recordId = (String) targetId;
        response.objectApiName = parentDescribe.getName();
        response.objectLabel = parentDescribe.getLabel();
        response.parentDeletable = parentDescribe.isDeletable();
        response.maxCountQueries = queryBudget;
        response.relationships = new List<RelationshipRow>();
        response.summary = new PreviewSummary();

        List<RelationshipRow> candidateRows = new List<RelationshipRow>();

        for (Schema.ChildRelationship relationship : parentDescribe.getChildRelationships()) {
            RelationshipRow row = buildRowSkeleton(relationship, ruleByChildObject);
            if (row == null) {
                continue;
            }
            candidateRows.add(row);
        }

        candidateRows.sort();

        Integer queriesUsed = 0;
        for (RelationshipRow row : candidateRows) {
            if (queriesUsed >= queryBudget) {
                row.wasEvaluated = false;
                row.countStatus = 'Not evaluated (query budget reached)';
            } else {
                evaluateCount(targetId, row);
                queriesUsed++;
            }

            if (includeZeroRows || row.relatedCount == null || row.relatedCount > 0 || row.isHighRisk || row.isCascadeDelete || row.isRestrictedDelete || !row.wasEvaluated) {
                response.relationships.add(row);
                rollupSummary(response.summary, row);
            }
        }

        response.summary.evaluatedRelationshipCount = queriesUsed;
        response.summary.totalRelationshipCount = candidateRows.size();
        response.summary.wasTruncated = queriesUsed < candidateRows.size();
        response.summary.visibleRelationshipCount = response.relationships.size();
        response.summary.riskHeadline = buildRiskHeadline(response.summary, response.parentDeletable);
        return response;
    }

    private static Integer normalizeQueryBudget(Integer maxCountQueries) {
        Integer proposed = maxCountQueries == null ? DEFAULT_MAX_COUNT_QUERIES : maxCountQueries;
        if (proposed < 1) {
            proposed = DEFAULT_MAX_COUNT_QUERIES;
        }
        if (proposed > ABSOLUTE_MAX_COUNT_QUERIES) {
            proposed = ABSOLUTE_MAX_COUNT_QUERIES;
        }
        return proposed;
    }

    private static Map<String, SafeDeleteRule__mdt> loadRules() {
        Map<String, SafeDeleteRule__mdt> ruleByChildObject = new Map<String, SafeDeleteRule__mdt>();
        for (SafeDeleteRule__mdt ruleRow : [
            SELECT DeveloperName, ChildObjectApiName__c, Behavior__c, Category__c, Notes__c
            FROM SafeDeleteRule__mdt
        ]) {
            if (!String.isBlank(ruleRow.ChildObjectApiName__c)) {
                ruleByChildObject.put(ruleRow.ChildObjectApiName__c.trim(), ruleRow);
            }
        }
        return ruleByChildObject;
    }

    private static RelationshipRow buildRowSkeleton(Schema.ChildRelationship relationship, Map<String, SafeDeleteRule__mdt> ruleByChildObject) {
        if (relationship == null || relationship.getChildSObject() == null || relationship.getField() == null) {
            return null;
        }

        Schema.DescribeSObjectResult childDescribe = relationship.getChildSObject().getDescribe();
        String childObjectApiName = childDescribe.getName();
        SafeDeleteRule__mdt ruleRow = ruleByChildObject.get(childObjectApiName);

        if (shouldExcludeChild(childDescribe, ruleRow)) {
            return null;
        }

        RelationshipRow row = new RelationshipRow();
        row.childObjectApiName = childObjectApiName;
        row.childObjectLabel = childDescribe.getLabel();
        row.childObjectLabelPlural = childDescribe.getLabelPlural();
        row.relationshipName = relationship.getRelationshipName();
        row.fieldApiName = relationship.getField().getDescribe().getName();
        row.isCascadeDelete = relationship.isCascadeDelete();
        row.isRestrictedDelete = relationship.isRestrictedDelete();
        row.isAccessible = childDescribe.isAccessible();
        row.isQueryable = childDescribe.isQueryable();
        row.isJunctionLike = isJunctionLike(childDescribe);
        row.category = deriveCategory(childObjectApiName, row.isJunctionLike, ruleRow);
        row.isHighRisk = deriveHighRisk(childObjectApiName, row.category, ruleRow);
        row.riskLevel = deriveRiskLevel(0, row.isCascadeDelete, row.isRestrictedDelete, row.isHighRisk, row.isJunctionLike);
        row.riskScore = preQueryPriority(row);
        row.ruleBehavior = ruleRow == null ? 'Auto' : ruleRow.Behavior__c;
        row.ruleNote = ruleRow == null ? null : ruleRow.Notes__c;
        row.wasEvaluated = false;
        row.countStatus = 'Pending';
        return row;
    }

    private static Boolean shouldExcludeChild(Schema.DescribeSObjectResult childDescribe, SafeDeleteRule__mdt ruleRow) {
        if (ruleRow != null && ruleRow.Behavior__c == 'Exclude') {
            return true;
        }

        String objectApiName = childDescribe.getName();
        for (String suffix : NOISE_SUFFIXES) {
            if (objectApiName.endsWith(suffix)) {
                return true;
            }
        }

        if (objectApiName.endsWith('Tag') || objectApiName.endsWith('VoteStat') || objectApiName.endsWith('DataStatistics')) {
            return true;
        }

        return false;
    }

    private static Boolean isJunctionLike(Schema.DescribeSObjectResult childDescribe) {
        Integer referenceFieldCount = 0;
        for (Schema.SObjectField fieldToken : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                referenceFieldCount++;
            }
            if (referenceFieldCount >= 2) {
                return true;
            }
        }
        return false;
    }

    private static String deriveCategory(String childObjectApiName, Boolean isJunctionLike, SafeDeleteRule__mdt ruleRow) {
        if (ruleRow != null && !String.isBlank(ruleRow.Category__c)) {
            return ruleRow.Category__c;
        }
        if (isJunctionLike) {
            return 'Junction';
        }
        if (childObjectApiName.contains('Content') || childObjectApiName.contains('Attachment') || childObjectApiName == 'Note') {
            return 'Files';
        }
        if (childObjectApiName == 'Task' || childObjectApiName == 'Event' || childObjectApiName == 'EmailMessage') {
            return 'Activity';
        }
        if (childObjectApiName.startsWith('ProcessInstance')) {
            return 'Approval';
        }
        if (childObjectApiName.contains('Feed')) {
            return 'Collaboration';
        }
        return 'Standard';
    }

    private static Boolean deriveHighRisk(String childObjectApiName, String category, SafeDeleteRule__mdt ruleRow) {
        if (ruleRow != null && ruleRow.Behavior__c == 'HighRisk') {
            return true;
        }
        if (HIGH_RISK_OBJECTS.contains(childObjectApiName)) {
            return true;
        }
        return category == 'Junction' || category == 'Files' || category == 'Approval' || category == 'Activity';
    }

    private static Integer preQueryPriority(RelationshipRow row) {
        Integer score = 0;
        score += row.isRestrictedDelete ? 50 : 0;
        score += row.isCascadeDelete ? 35 : 0;
        score += row.isHighRisk ? 25 : 0;
        score += row.isJunctionLike ? 15 : 0;
        return score;
    }

    private static void evaluateCount(Id targetId, RelationshipRow row) {
        row.wasEvaluated = true;
        if (!row.isAccessible || !row.isQueryable) {
            row.countStatus = 'Not evaluated (insufficient object access)';
            row.relatedCount = null;
            return;
        }

        try {
            String query = 'SELECT COUNT() FROM ' + row.childObjectApiName + ' WHERE ' + row.fieldApiName + ' = :targetId';
            row.relatedCount = Database.countQuery(query);
            row.countStatus = 'Evaluated';
            row.riskLevel = deriveRiskLevel(row.relatedCount, row.isCascadeDelete, row.isRestrictedDelete, row.isHighRisk, row.isJunctionLike);
        } catch (Exception ex) {
            row.relatedCount = null;
            row.countStatus = 'Not evaluated (' + ex.getMessage() + ')';
        }
    }

    private static String deriveRiskLevel(Integer relatedCount, Boolean isCascadeDelete, Boolean isRestrictedDelete, Boolean isHighRisk, Boolean isJunctionLike) {
        Integer score = relatedCount == null ? 0 : Math.min(relatedCount, 20);
        score += isCascadeDelete ? 30 : 0;
        score += isRestrictedDelete ? 35 : 0;
        score += isHighRisk ? 20 : 0;
        score += isJunctionLike ? 15 : 0;

        if (score >= 55) {
            return 'Critical';
        }
        if (score >= 30) {
            return 'High';
        }
        if (score >= 12) {
            return 'Medium';
        }
        return 'Low';
    }

    private static void rollupSummary(PreviewSummary summary, RelationshipRow row) {
        summary.totalRelatedChildren += row.relatedCount == null ? 0 : row.relatedCount;
        summary.cascadeRelationshipCount += row.isCascadeDelete ? 1 : 0;
        summary.restrictedRelationshipCount += row.isRestrictedDelete ? 1 : 0;
        summary.highRiskRelationshipCount += row.isHighRisk ? 1 : 0;
        summary.junctionRelationshipCount += row.isJunctionLike ? 1 : 0;

        if (row.riskLevel == 'Critical') {
            summary.criticalRelationshipCount++;
        } else if (row.riskLevel == 'High') {
            summary.highRelationshipCount++;
        }
    }

    private static String buildRiskHeadline(PreviewSummary summary, Boolean parentDeletable) {
        if (!parentDeletable) {
            return 'The parent object is not deletable for the current user context.';
        }
        if (summary.criticalRelationshipCount > 0 || summary.restrictedRelationshipCount > 0) {
            return 'Critical delete impact signals were detected. Review every flagged relationship before deleting.';
        }
        if (summary.highRiskRelationshipCount > 0 || summary.cascadeRelationshipCount > 0) {
            return 'This record has meaningful downstream impact. Review flagged child relationships before deleting.';
        }
        return 'No obvious high-risk delete signals were found in the evaluated relationships.';
    }

    public class PreviewResponse {
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public Boolean parentDeletable;
        @AuraEnabled public Integer maxCountQueries;
        @AuraEnabled public PreviewSummary summary;
        @AuraEnabled public List<RelationshipRow> relationships;
    }

    public class PreviewSummary {
        @AuraEnabled public Integer totalRelatedChildren = 0;
        @AuraEnabled public Integer totalRelationshipCount = 0;
        @AuraEnabled public Integer visibleRelationshipCount = 0;
        @AuraEnabled public Integer evaluatedRelationshipCount = 0;
        @AuraEnabled public Integer cascadeRelationshipCount = 0;
        @AuraEnabled public Integer restrictedRelationshipCount = 0;
        @AuraEnabled public Integer highRiskRelationshipCount = 0;
        @AuraEnabled public Integer junctionRelationshipCount = 0;
        @AuraEnabled public Integer criticalRelationshipCount = 0;
        @AuraEnabled public Integer highRelationshipCount = 0;
        @AuraEnabled public Boolean wasTruncated = false;
        @AuraEnabled public String riskHeadline;
    }

    public class RelationshipRow implements Comparable {
        @AuraEnabled public String childObjectApiName;
        @AuraEnabled public String childObjectLabel;
        @AuraEnabled public String childObjectLabelPlural;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String category;
        @AuraEnabled public String ruleBehavior;
        @AuraEnabled public String ruleNote;
        @AuraEnabled public Integer relatedCount;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public String countStatus;
        @AuraEnabled public Boolean wasEvaluated;
        @AuraEnabled public Boolean isCascadeDelete;
        @AuraEnabled public Boolean isRestrictedDelete;
        @AuraEnabled public Boolean isHighRisk;
        @AuraEnabled public Boolean isJunctionLike;
        @AuraEnabled public Boolean isAccessible;
        @AuraEnabled public Boolean isQueryable;

        public Integer compareTo(Object otherObj) {
            RelationshipRow otherRow = (RelationshipRow) otherObj;
            Integer leftScore = riskScore == null ? 0 : riskScore;
            Integer rightScore = otherRow.riskScore == null ? 0 : otherRow.riskScore;
            if (leftScore == rightScore) {
                String leftName = childObjectApiName == null ? '' : childObjectApiName;
                String rightName = otherRow.childObjectApiName == null ? '' : otherRow.childObjectApiName;
                return leftName.compareToIgnoreCase(rightName);
            }
            return rightScore - leftScore;
        }
    }
}
