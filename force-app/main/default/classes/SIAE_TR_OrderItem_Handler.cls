/**
 * @description Handler del trigger SIAE_TR_OrderItem.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
public without sharing class SIAE_TR_OrderItem_Handler implements SIAE_TR_I_Trigger_Handler {

    public static Boolean triggerOff = false;
    private static Boolean isExecuting = false;

    /**
     * @description Permette di spegnere il trigger da codice/test.
     */
    public Boolean skipTrigger() {
        return triggerOff;
    }

    public Boolean stopRecursion() {
        return isExecuting;
    }

    /**
     * @description Reset del flag ricorsione chiamato dal dispatcher al termine dell'esecuzione.
     */
    public void executedTrigger() {
        isExecuting = false;
    }

    public void onBeforeInsert(List<SObject> listNewS) {}

    public void onBeforeUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {}

    public void onBeforeDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterInsert(Map<Id, SObject> mapNewS) {}

    /**
     * @description Gestione after update OrderItem.
     *              Aggiorna la tassazione DA tramite utility dedicata.
     */
    public void onAfterUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {
        if (mapOldS == null || mapOldS.isEmpty()) return;
        if (mapNewS == null || mapNewS.isEmpty()) return;

        isExecuting = true;

        Map<Id, OrderItem> oldMap = (Map<Id, OrderItem>) mapOldS;
        Map<Id, OrderItem> newMap = (Map<Id, OrderItem>) mapNewS;

        SIAE_TR_OrderItem_U_ManageTaxes.updateTaxFields(
            newMap.values(),
            oldMap
        );
    }

    public void onAfterDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterUndelete(Map<Id, SObject> mapNewS) {}
}