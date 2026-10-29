/**
 * @description Handler for Account Trigger
 */
public without sharing class SIAE_TR_Account_Handler implements SIAE_TR_I_Trigger_Handler {

    public static Boolean triggerOff = false;

    public Boolean skipTrigger() {
        return triggerOff;
    }

    public Boolean stopRecursion() {
        return false;
    }

    public void executedTrigger() {}

    public void onBeforeInsert(List<SObject> listNewS) {}

    public void onBeforeUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {}

    public void onBeforeDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterInsert(Map<Id, SObject> mapNewS) {
        if (mapNewS == null || mapNewS.isEmpty()) return;

        SIAE_TR_Account_U_ManageBillingAccount.manageAfterInsert(
            (Map<Id, Account>) mapNewS
        );
    }

    public void onAfterUpdate(Map<Id, SObject> mapOldS, Map<Id, SObject> mapNewS) {
        if (mapOldS == null || mapOldS.isEmpty()) return;
        if (mapNewS == null || mapNewS.isEmpty()) return;

        SIAE_TR_Account_U_ManageBillingAccount.manageAfterUpdate(
            (Map<Id, Account>) mapOldS,
            (Map<Id, Account>) mapNewS
        );
    }

    public void onAfterDelete(Map<Id, SObject> mapOldS) {}

    public void onAfterUndelete(Map<Id, SObject> mapNewS) {}
}