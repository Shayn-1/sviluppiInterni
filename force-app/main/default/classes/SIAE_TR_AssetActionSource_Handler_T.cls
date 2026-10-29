/**
 * @description Test class for SIAE_TR_AssetActionSource_Handler.
 *              Copre i metodi dell'interfaccia SIAE_TR_I_Trigger_Handler,
 *              i flag triggerOff/isExecuting e la delega ad onAfterInsert/onAfterUpdate.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
@isTest
private class SIAE_TR_AssetActionSource_Handler_T {

    @isTest
    static void shouldReflectTriggerOffFlag() {
        SIAE_TR_AssetActionSource_Handler.triggerOff = false;
        SIAE_TR_AssetActionSource_Handler handler = new SIAE_TR_AssetActionSource_Handler();

        Assert.areEqual(false, handler.skipTrigger(), 'Default: trigger non skippato.');

        SIAE_TR_AssetActionSource_Handler.triggerOff = true;
        Assert.areEqual(true, handler.skipTrigger(), 'triggerOff=true deve riflettersi su skipTrigger().');

        SIAE_TR_AssetActionSource_Handler.triggerOff = false;
    }

    @isTest
    static void shouldCoverNoOpMethods() {
        SIAE_TR_AssetActionSource_Handler handler = new SIAE_TR_AssetActionSource_Handler();

        Assert.areEqual(false, handler.stopRecursion(), 'Default: nessuna ricorsione bloccata.');

        handler.onBeforeInsert(new List<SObject>());
        handler.onBeforeUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        handler.onBeforeDelete(new Map<Id, SObject>());
        handler.onAfterDelete(new Map<Id, SObject>());
        handler.onAfterUndelete(new Map<Id, SObject>());

        Assert.isTrue(true, 'Metodi no-op eseguiti senza eccezioni.');
    }

    @isTest
    static void shouldDoNothing_OnAfterInsertOrUpdate_WhenMapIsNullOrEmpty() {
        SIAE_TR_AssetActionSource_Handler handler = new SIAE_TR_AssetActionSource_Handler();

        handler.onAfterInsert(null);
        handler.onAfterInsert(new Map<Id, SObject>());
        Assert.areEqual(false, handler.stopRecursion(), 'Map nulla/vuota su onAfterInsert non deve marcare la ricorsione.');

        handler.onAfterUpdate(new Map<Id, SObject>(), null);
        handler.onAfterUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        Assert.areEqual(false, handler.stopRecursion(), 'Map nulla/vuota su onAfterUpdate non deve marcare la ricorsione.');
    }

    @isTest
    static void shouldSetAndResetRecursionFlag_OnAfterInsert() {
        Account acc = SIAE_TestDataFactory.createAccount(true);
        Asset asset = new Asset(Name = 'Test Asset Handler', AccountId = acc.Id);
        insert asset;

        AssetAction aa = new AssetAction(
            AssetId = asset.Id,
            Type = 'Change',
            CategoryEnum = 'Other',
            ActionDate = System.now(),
            QuantityChange = 0,
            MrrChange = 0,
            Amount = 0
        );
        insert aa;

        AssetActionSource aas = new AssetActionSource(AssetActionId = aa.Id);
        SIAE_TR_AssetActionSource_Handler handler = new SIAE_TR_AssetActionSource_Handler();

        Test.startTest();
        insert aas;
        Map<Id, AssetActionSource> aasMap = new Map<Id, AssetActionSource>{ aas.Id => aas };
        handler.onAfterInsert(aasMap);
        Test.stopTest();

        Assert.areEqual(true, handler.stopRecursion(), 'onAfterInsert con map non vuota deve marcare isExecuting=true.');

        handler.executedTrigger();
        Assert.areEqual(false, handler.stopRecursion(), 'executedTrigger() deve resettare isExecuting.');
    }
}