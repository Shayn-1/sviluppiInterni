public without sharing class SIAE_TR_AssetActionSource_Handler implements SIAE_TR_I_Trigger_Handler {

    public static Boolean triggerOff = false;
    private static Boolean isExecuting = false;

    public Boolean skipTrigger() {
        return triggerOff;
    }

    public Boolean stopRecursion() {
        return isExecuting;
    }

    public void executedTrigger() {
        isExecuting = false;
    }

    public void onBeforeInsert(List<SObject> listNewS) {}

    public void onBeforeUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {}

    public void onBeforeDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterInsert(Map<Id, SObject> mapNewS) {
        if (mapNewS == null || mapNewS.isEmpty()) return;

        isExecuting = true;

        SIAE_TR_AssetActionSource_U_CopyToAsset.copyFieldsToAsset(
            (Map<Id, AssetActionSource>) mapNewS
        );
    }

    public void onAfterUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {
        if (mapNewS == null || mapNewS.isEmpty()) return;

        isExecuting = true;

        SIAE_TR_AssetActionSource_U_CopyToAsset.copyFieldsToAsset(
            (Map<Id, AssetActionSource>) mapNewS
        );
    }

    public void onAfterDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterUndelete(Map<Id, SObject> mapNewS) {}
}