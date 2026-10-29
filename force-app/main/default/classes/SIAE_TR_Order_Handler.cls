/**
 * @description SIAE_TR_Order_Handler - Handler for Order Trigger
 */
public without sharing class SIAE_TR_Order_Handler implements SIAE_TR_I_Trigger_Handler {

    public static Boolean triggerOff = false;

    public Boolean skipTrigger() { 
        return triggerOff;
        // Eventuale futura custom permission:
        // return triggerOff || FeatureManagement.checkPermission('SIAE_SkipTrigger_Order');
    }

    public Boolean stopRecursion() {
        return false;
    }

    public void executedTrigger() {
        // Al momento non serve bloccare tutto il trigger per evento
        // La protezione anti-ripetizione delle action è gestita nella utility action
    }

    public void onBeforeInsert(List<SObject> listNews) {
        // Non gestito ancora
    }

    public void onBeforeUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {
        Map<Id, Order> mapOld = (Map<Id, Order>) mapOldS;
        Map<Id, Order> mapNew = (Map<Id, Order>) mapNewS;

        SIAE_TR_Order_U_ManageStatus.managePagataDdaStatus(mapOld, mapNew);
    }

    public void onBeforeDelete(Map<Id, SObject> mapOld) {
        // Non gestito ancora
    }

    public void onAfterInsert(Map<Id, SObject> mapNew) {
        // Non gestito ancora
    }

    public void onAfterUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {
        Map<Id, Order> mapOld = (Map<Id, Order>) mapOldS;
        Map<Id, Order> mapNew = (Map<Id, Order>) mapNewS;

        SIAE_TR_Order_U_ManageActions.manageOrderActions(mapOld, mapNew);
    }

    public void onAfterDelete(Map<Id, SObject> mapOld) {
        // Non gestito per questa implementazione.
    }

    public void onAfterUndelete(Map<Id, SObject> mapNew) {
        // Non gestito per questa implementazione.
    }
}