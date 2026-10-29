/**
 * @description Test class for SIAE_TR_AssetActionSource_U_CopyToAsset.
 *              Logica: SIAE_CS_FromAssetActionSourceToAsset__c mappa i campi da copiare
 *              da AssetActionSource verso l'Asset collegato (via AssetAction.AssetId).
 *              Il trigger su AssetActionSource (after insert/update) invoca il metodo,
 *              quindi i record vengono inseriti/aggiornati realmente per esercitare il flusso end-to-end.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
@isTest
private class SIAE_TR_AssetActionSrc_U_CopyToAsset_T {

    private static final String SOURCE_FIELD = 'SIAE_TypeOfCoverage__c';
    private static final String TARGET_FIELD = 'SIAE_TypeOfCoverage__c';
    private static final String SOURCE_FIELD_2 = 'SIAE_DCCardId__c';
    private static final String TARGET_FIELD_2 = 'SIAE_DCCardId__c';

    @TestSetup
    static void setupTestData() {
        // Ripulisce eventuali mapping già presenti nell'org per garantire un test deterministico.
        delete [SELECT Id FROM SIAE_CS_FromAssetActionSourceToAsset__c];

        insert new List<SIAE_CS_FromAssetActionSourceToAsset__c>{
            new SIAE_CS_FromAssetActionSourceToAsset__c(
                Name = 'Mapping1',
                SIAE_SourceField__c = SOURCE_FIELD,
                SIAE_TargetField__c = TARGET_FIELD
            ),
            new SIAE_CS_FromAssetActionSourceToAsset__c(
                Name = 'Mapping2',
                SIAE_SourceField__c = SOURCE_FIELD_2,
                SIAE_TargetField__c = TARGET_FIELD_2
            )
        };

        Account acc = SIAE_TestDataFactory.createAccount(true);
        insert new Asset(Name = 'Test Asset', AccountId = acc.Id);
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    private static Asset getAsset() {
        return [SELECT Id FROM Asset LIMIT 1];
    }

    private static AssetAction createAssetAction(Id assetId, Boolean doInsert) {
        AssetAction aa = new AssetAction(
            AssetId = assetId,
            Type = 'Change',
            CategoryEnum = 'Other',
            ActionDate = System.now(),
            QuantityChange = 0,
            MrrChange = 0,
            Amount = 0
        );
        if (doInsert) insert aa;
        return aa;
    }

    private static AssetActionSource createAssetActionSource(Id assetActionId, String typeOfCoverage, String dcCardId, Boolean doInsert) {
        AssetActionSource aas = new AssetActionSource(
            AssetActionId = assetActionId,
            SIAE_TypeOfCoverage__c = typeOfCoverage,
            SIAE_DCCardId__c = dcCardId
        );
        if (doInsert) insert aas;
        return aas;
    }

    // ─── copyFieldsToAsset: end-to-end via trigger ─────────────────────────

    @isTest
    static void shouldCopyMappedFields_OnAssetActionSourceInsert() {
        Asset asset = getAsset();
        AssetAction aa = createAssetAction(asset.Id, true);

        Test.startTest();
        createAssetActionSource(aa.Id, 'Annuale', 'DC-001', true);
        Test.stopTest();

        Asset updated = [SELECT SIAE_TypeOfCoverage__c, SIAE_DCCardId__c FROM Asset WHERE Id = :asset.Id];
        Assert.areEqual('Annuale', updated.SIAE_TypeOfCoverage__c, 'SIAE_TypeOfCoverage__c deve essere copiato sull Asset.');
        Assert.areEqual('DC-001', updated.SIAE_DCCardId__c, 'SIAE_DCCardId__c deve essere copiato sull Asset.');
    }

    @isTest
    static void shouldCopyMappedFields_OnAssetActionSourceUpdate() {
        Asset asset = getAsset();
        AssetAction aa = createAssetAction(asset.Id, true);
        AssetActionSource aas = createAssetActionSource(aa.Id, 'Annuale', 'DC-001', true);

        Test.startTest();
        aas.SIAE_TypeOfCoverage__c = 'Semestrale';
        aas.SIAE_DCCardId__c = 'DC-002';
        update aas;
        Test.stopTest();

        Asset updated = [SELECT SIAE_TypeOfCoverage__c, SIAE_DCCardId__c FROM Asset WHERE Id = :asset.Id];
        Assert.areEqual('Semestrale', updated.SIAE_TypeOfCoverage__c, 'Il valore aggiornato deve essere ricopiato sull Asset.');
        Assert.areEqual('DC-002', updated.SIAE_DCCardId__c, 'Il valore aggiornato deve essere ricopiato sull Asset.');
    }

    @isTest
    static void shouldUpdateAssetOnce_WhenMultipleAssetActionSourcesTargetSameAsset() {
        Asset asset = getAsset();
        AssetAction aa1 = createAssetAction(asset.Id, true);
        AssetAction aa2 = createAssetAction(asset.Id, true);

        List<AssetActionSource> toInsert = new List<AssetActionSource>{
            createAssetActionSource(aa1.Id, 'Annuale', 'DC-001', false),
            createAssetActionSource(aa2.Id, 'Annuale', 'DC-001', false)
        };

        Test.startTest();
        insert toInsert;
        Test.stopTest();

        Asset updated = [SELECT SIAE_TypeOfCoverage__c, SIAE_DCCardId__c FROM Asset WHERE Id = :asset.Id];
        Assert.areEqual('Annuale', updated.SIAE_TypeOfCoverage__c, 'Asset aggiornato una sola volta con i valori mappati.');
        Assert.areEqual('DC-001', updated.SIAE_DCCardId__c, 'Asset aggiornato una sola volta con i valori mappati.');
    }

    // ─── copyFieldsToAsset: direct unit calls (edge cases) ─────────────────

    @isTest
    static void shouldDoNothing_WhenMapIsNull() {
        Test.startTest();
        SIAE_TR_AssetActionSource_U_CopyToAsset.copyFieldsToAsset(null);
        Test.stopTest();
        Assert.isTrue(true, 'Map nulla gestita senza eccezioni.');
    }

    @isTest
    static void shouldDoNothing_WhenMapIsEmpty() {
        Test.startTest();
        SIAE_TR_AssetActionSource_U_CopyToAsset.copyFieldsToAsset(new Map<Id, AssetActionSource>());
        Test.stopTest();
        Assert.isTrue(true, 'Map vuota gestita senza eccezioni.');
    }

    @isTest
    static void shouldNotUpdateAsset_WhenNoCustomSettingRecordsConfigured() {
        delete [SELECT Id FROM SIAE_CS_FromAssetActionSourceToAsset__c];

        Asset asset = getAsset();
        AssetAction aa = createAssetAction(asset.Id, true);
        AssetActionSource aas = createAssetActionSource(aa.Id, 'Annuale', 'DC-001', true);

        Test.startTest();
        SIAE_TR_AssetActionSource_U_CopyToAsset.copyFieldsToAsset(
            new Map<Id, AssetActionSource>{ aas.Id => aas }
        );
        Test.stopTest();

        Asset updated = [SELECT SIAE_TypeOfCoverage__c FROM Asset WHERE Id = :asset.Id];
        Assert.isNull(updated.SIAE_TypeOfCoverage__c, 'Senza mapping configurato, nessun campo deve essere copiato.');
    }

    @isTest
    static void shouldSkipInvalidMappings_WhenSourceOrTargetFieldDoesNotExist() {
        insert new SIAE_CS_FromAssetActionSourceToAsset__c(
            Name = 'InvalidMapping',
            SIAE_SourceField__c = 'SIAE_NonExistentField__c',
            SIAE_TargetField__c = 'SIAE_NonExistentField__c'
        );

        Asset asset = getAsset();
        AssetAction aa = createAssetAction(asset.Id, true);

        Test.startTest();
        createAssetActionSource(aa.Id, 'Annuale', 'DC-001', true);
        Test.stopTest();

        Asset updated = [SELECT SIAE_TypeOfCoverage__c, SIAE_DCCardId__c FROM Asset WHERE Id = :asset.Id];
        Assert.areEqual('Annuale', updated.SIAE_TypeOfCoverage__c, 'I mapping validi restano applicati.');
        Assert.areEqual('DC-001', updated.SIAE_DCCardId__c, 'I mapping validi restano applicati.');
    }

}