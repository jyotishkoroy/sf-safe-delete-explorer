import { api, LightningElement, track } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import preview from '@salesforce/apex/SafeDeleteExplorerService.preview';

export default class SafeDeleteExplorer extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadPreview();
        }
    }
    @api showDeleteAction = false;
    @api showZeroCountRows = false;
    @api maxCountQueries = 70;

    @track preview;
    @track errorMessage;
    @track isLoading = false;
    @track manualRecordId = '';
    @track filterText = '';
    @track acknowledged = false;

    connectedCallback() {
        this.loadPreview();
    }

    get activeRecordId() {
        return (this.recordId || this.manualRecordId || '').trim();
    }

    get showManualInput() {
        return !this.recordId;
    }

    get deleteDisabled() {
        return !this.acknowledged || !this.showDeleteAction || !this.activeRecordId;
    }

    get headlineClass() {
        if (!this.preview) {
            return 'headline';
        }
        if (this.preview.summary.criticalRelationshipCount > 0 || this.preview.summary.restrictedRelationshipCount > 0) {
            return 'headline headlineCritical';
        }
        if (this.preview.summary.highRiskRelationshipCount > 0 || this.preview.summary.cascadeRelationshipCount > 0) {
            return 'headline headlineWarn';
        }
        return 'headline headlineSafe';
    }

    get filteredRelationships() {
        if (!this.preview || !this.preview.relationships) {
            return [];
        }

        const filter = (this.filterText || '').trim().toLowerCase();
        const rows = this.preview.relationships.map((row, index) => ({
            ...row,
            rowKey: `${row.childObjectApiName}-${row.fieldApiName}-${index}`,
            displayCount: row.relatedCount === null || row.relatedCount === undefined ? '—' : row.relatedCount,
            riskClass: `riskBadge risk${row.riskLevel}`
        }));

        if (!filter) {
            return rows;
        }

        return rows.filter((row) => {
            return [
                row.childObjectApiName,
                row.childObjectLabel,
                row.childObjectLabelPlural,
                row.fieldApiName,
                row.category,
                row.riskLevel,
                row.countStatus
            ]
                .filter(Boolean)
                .join(' ')
                .toLowerCase()
                .includes(filter);
        });
    }

    handleManualRecordIdChange(event) {
        this.manualRecordId = event.target.value;
    }

    handleFilterChange(event) {
        this.filterText = event.target.value;
    }

    handleAcknowledgeChange(event) {
        this.acknowledged = event.target.checked;
    }

    async handleRefresh() {
        await this.loadPreview();
    }

    async loadPreview() {
        const activeRecordId = this.activeRecordId;
        if (!activeRecordId) {
            this.preview = undefined;
            this.errorMessage = this.recordId ? undefined : 'Enter a record Id to evaluate delete impact.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;
        this.acknowledged = false;

        try {
            this.preview = await preview({
                recordId: activeRecordId,
                showZeroCountRows: this.showZeroCountRows,
                maxCountQueries: Number(this.maxCountQueries)
            });
        } catch (error) {
            this.preview = undefined;
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDelete() {
        if (this.deleteDisabled) {
            return;
        }

        try {
            await deleteRecord(this.activeRecordId);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Record deleted',
                    message: 'The record was deleted successfully.',
                    variant: 'success'
                })
            );

            if (this.preview?.objectApiName) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: this.preview.objectApiName,
                        actionName: 'home'
                    }
                });
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Delete failed',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        }
    }

    normalizeError(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error.body?.message || error.message || 'An unexpected error occurred.';
    }
}
