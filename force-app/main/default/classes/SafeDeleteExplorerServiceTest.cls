/**
 * Copyright 2026 Jyotishko Roy
 * Licensed under the Apache License, Version 2.0.
 */
@IsTest
private class SafeDeleteExplorerServiceTest {
    @IsTest
    static void preview_counts_child_relationships() {
        Account acct = new Account(Name = 'Preview Parent');
        insert acct;

        insert new List<Contact>{
            new Contact(LastName = 'One', AccountId = acct.Id),
            new Contact(LastName = 'Two', AccountId = acct.Id)
        };

        Test.startTest();
        SafeDeleteExplorerService.PreviewResponse response =
            SafeDeleteExplorerService.preview(acct.Id, false, 20);
        Test.stopTest();

        System.assertEquals('Account', response.objectApiName);
        System.assertNotEquals(null, response.summary);
        System.assert(response.relationships.size() > 0, 'Expected at least one child relationship row.');

        SafeDeleteExplorerService.RelationshipRow contactRow;
        for (SafeDeleteExplorerService.RelationshipRow row : response.relationships) {
            if (row.childObjectApiName == 'Contact' && row.fieldApiName == 'AccountId') {
                contactRow = row;
                break;
            }
        }

        System.assertNotEquals(null, contactRow, 'The Contact child relationship should be present.');
        System.assertEquals(2, contactRow.relatedCount);
        System.assertEquals(true, contactRow.wasEvaluated);
    }

    @IsTest
    static void preview_rejects_invalid_id() {
        try {
            SafeDeleteExplorerService.preview('not-a-record-id', false, 20);
            System.assert(false, 'Expected an AuraHandledException for an invalid Id.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('not valid'));
        }
    }

    @IsTest
    static void custom_metadata_rules_are_present() {
        List<SafeDeleteRule__mdt> rules = [
            SELECT DeveloperName, ChildObjectApiName__c, Behavior__c
            FROM SafeDeleteRule__mdt
        ];
        System.assert(rules.size() >= 1, 'Expected packaged custom metadata rules to be present.');
    }
}
