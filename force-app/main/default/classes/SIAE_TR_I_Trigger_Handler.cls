/**
 * @description SIAE_TR_I_TriggerHandler - Interface for Trigger Handlers
 */
public interface SIAE_TR_I_Trigger_Handler {

    Boolean skipTrigger();

    Boolean stopRecursion();

    void executedTrigger();

    void onBeforeInsert(List<SObject> listNew);

    void onBeforeUpdate(Map<Id, SObject> mapOld, Map<Id, SObject> mapNew);

    void onBeforeDelete(Map<Id, SObject> mapOld);

    void onAfterInsert(Map<Id, SObject> mapNew);

    void onAfterUpdate(Map<Id, SObject> mapOld, Map<Id, SObject> mapNew);

    void onAfterDelete(Map<Id, SObject> mapOld);

    void onAfterUndelete(Map<Id, SObject> mapNew);
}