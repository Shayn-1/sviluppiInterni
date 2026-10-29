public without sharing class SIAE_TR_AssetActionSource_U_CopyToAsset {

    public static void copyFieldsToAsset(Map<Id, AssetActionSource> aasMap) {
        if (aasMap == null || aasMap.isEmpty()) return;

        Set<Id> aasIds = aasMap.keySet();

        List<SIAE_CS_FromAssetActionSourceToAsset__c> settings =
            SIAE_CS_FromAssetActionSourceToAsset__c.getAll().values();

        if (settings == null || settings.isEmpty()) return;

        Set<String> sourceFields = new Set<String>();
        Map<String, String> sourceToTargetField = new Map<String, String>();

        Map<String, Schema.SObjectField> aasFieldMap =
            Schema.SObjectType.AssetActionSource.fields.getMap();

        Map<String, Schema.SObjectField> assetFieldMap =
            Schema.SObjectType.Asset.fields.getMap();

        for (SIAE_CS_FromAssetActionSourceToAsset__c setting : settings) {
            if (
                String.isBlank(setting.SIAE_SourceField__c) ||
                String.isBlank(setting.SIAE_TargetField__c)
            ) {
                continue;
            }

            String sourceField = setting.SIAE_SourceField__c.trim();
            String targetField = setting.SIAE_TargetField__c.trim();

            if (!aasFieldMap.containsKey(sourceField)) continue;
            if (!assetFieldMap.containsKey(targetField)) continue;

            sourceFields.add(sourceField);
            sourceToTargetField.put(sourceField, targetField);
        }

        if (sourceFields.isEmpty()) return;

        List<String> selectFields = new List<String>();
        selectFields.add('Id');
        selectFields.add('AssetAction.AssetId');
        selectFields.addAll(sourceFields);

        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM AssetActionSource ' +
            ' WHERE Id IN :aasIds';

        System.debug('SIAE_TR_AssetActionSource_U_CopyToAsset SOQL = ' + soql);

        List<AssetActionSource> aasList = Database.query(soql);

        Map<Id, Asset> assetsToUpdate = new Map<Id, Asset>();

        for (AssetActionSource aas : aasList) {
            if (aas.AssetAction == null || aas.AssetAction.AssetId == null) {
                continue;
            }

            Id assetId = aas.AssetAction.AssetId;

            if (!assetsToUpdate.containsKey(assetId)) {
                assetsToUpdate.put(assetId, new Asset(Id = assetId));
            }

            Asset assetToUpdate = assetsToUpdate.get(assetId);

            for (String sourceField : sourceToTargetField.keySet()) {
                String targetField = sourceToTargetField.get(sourceField);
                assetToUpdate.put(targetField, aas.get(sourceField));
            }
        }

        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate.values();
        }
    }
}