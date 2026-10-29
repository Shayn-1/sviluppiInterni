/**
 * @description       : 
 * @author            : Iuliano Gaetano - gaetano.iuliano@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-28-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public class SIAE_UTIL_DirittiConnessiEngine {

    public static SIAE_DTO_DirittiConnessiResult calculate(List<RCASalesTransaction.ItemNode> listOfSalesItemNode, Set<String> setOfProductCode, Map<String,Product2> mapProductIdProduct) {
        SIAE_DTO_DirittiConnessiResult result = new SIAE_DTO_DirittiConnessiResult();

        if (listOfSalesItemNode == null || listOfSalesItemNode.isEmpty()) {
            return result;
        }


        if (setOfProductCode.isEmpty()) {
            return result;
        }

        Map<String, SIAE_DirittiConnessiConfig__mdt> configByProductCode = loadConfigs(setOfProductCode);

        Set<String> configNames = new Set<String>();
        for (SIAE_DirittiConnessiConfig__mdt config : configByProductCode.values()) {
            configNames.add(config.DeveloperName);
        }

        Map<String, List<SIAE_DirittiConnessiTariffa__c>> tariffeByConfig = loadTariffe(configNames);

        Map<String, List<SIAE_DirittiConnessiRule__c>> regoleByConfig = loadRegole(configNames);

        for (RCASalesTransaction.ItemNode itemNode : listOfSalesItemNode) {
            if (String.isBlank(itemNode.productId) || !mapProductIdProduct.containsKey(itemNode.productId) || String.isBlank(mapProductIdProduct.get(itemNode.productId).ProductCode)) {
                continue;
            }

            String productCode = mapProductIdProduct.get(itemNode.productId).ProductCode;
            SIAE_DirittiConnessiConfig__mdt config = configByProductCode.get(productCode);

            if (config == null || !config.SIAE_CalculationEnabled__c) {
                continue;
            }

            Map<String, String> attributi = itemNode.attributeValueByCode != null
                ? itemNode.attributeValueByCode
                : new Map<String, String>();

            Date effectiveDate = RCAValueConverter.asDate(itemNode.effectiveFrom);

            List<SIAE_DirittiConnessiRule__c> regole = filterActiveRules(
                regoleByConfig.containsKey(config.DeveloperName)
                    ? regoleByConfig.get(config.DeveloperName)
                    : new List<SIAE_DirittiConnessiRule__c>(),
                effectiveDate
            );

            List<SIAE_DirittiConnessiTariffa__c> tariffe = filterActiveRates(
                tariffeByConfig.containsKey(config.DeveloperName)
                    ? tariffeByConfig.get(config.DeveloperName)
                    : new List<SIAE_DirittiConnessiTariffa__c>(),
                effectiveDate
            );

            SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail = SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                itemNode,
                attributi,
                regole,
                tariffe,
                config
            );

            result.dettagliPerOrderItem.add(detail);
            result.totaleComplessivo += detail.subtotale;
        }

        return result;
    }

    @TestVisible
    private static Map<String, SIAE_DirittiConnessiConfig__mdt> loadConfigs(Set<String> productCodes) {
        Map<String, SIAE_DirittiConnessiConfig__mdt> configByCode = new Map<String, SIAE_DirittiConnessiConfig__mdt>();
        
        if (productCodes == null || productCodes.isEmpty()) {
            return configByCode;
        }

        List<SIAE_DirittiConnessiConfig__mdt> listOfConfiguration = [
            SELECT DeveloperName, SIAE_ProductCode__c, SIAE_CalculationEnabled__c
            FROM SIAE_DirittiConnessiConfig__mdt
            WHERE SIAE_ProductCode__c IN :productCodes
        ];

        for (SIAE_DirittiConnessiConfig__mdt config : listOfConfiguration) {
            configByCode.put(config.SIAE_ProductCode__c, config);
        }
        return configByCode;
    }

    @TestVisible
    private static Map<String, List<SIAE_DirittiConnessiTariffa__c>> loadTariffe(Set<String> configNames) {
        Map<String, List<SIAE_DirittiConnessiTariffa__c>> tariffeByConfig = new Map<String, List<SIAE_DirittiConnessiTariffa__c>>();
        
        if (configNames == null || configNames.isEmpty()) {
            return tariffeByConfig;
        }

        List<SIAE_DirittiConnessiTariffa__c> listOfRate = [
            SELECT Name, SIAE_ConfigName__c, SIAE_DeviceType__c,
                   SIAE_BracketFrom__c, SIAE_BracketTo__c, SIAE_Amount__c,
                   SIAE_ExtraAmountPerUnit__c, SIAE_ExtraUnitSize__c, SIAE_ExtraPercentage__c,SIAE_SecondaryParameterValue__c,
                   SIAE_CoeffStagionalitaDC__c, SIAE_CoeffStagionalitaDC_Semestrale__c, SIAE_CoeffStagionalitaDC_Trimestrale__c,
                   SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
            FROM SIAE_DirittiConnessiTariffa__c 
            WHERE SIAE_ConfigName__c IN :configNames
            ORDER BY SIAE_ConfigName__c, SIAE_DeviceType__c, SIAE_BracketFrom__c ASC
        ];

        for (SIAE_DirittiConnessiTariffa__c rate : listOfRate) {
            if (!tariffeByConfig.containsKey(rate.SIAE_ConfigName__c)) {
                tariffeByConfig.put(rate.SIAE_ConfigName__c, new List<SIAE_DirittiConnessiTariffa__c>());
            }
            tariffeByConfig.get(rate.SIAE_ConfigName__c).add(rate);
        }
        return tariffeByConfig;
    }

    @TestVisible
    private static Map<String, List<SIAE_DirittiConnessiRule__c>> loadRegole(Set<String> configNames) {
        Map<String, List<SIAE_DirittiConnessiRule__c>> regoleByConfig = new Map<String, List<SIAE_DirittiConnessiRule__c>>();
        
        if (configNames == null || configNames.isEmpty()) {
            return regoleByConfig;
        }

        List<SIAE_DirittiConnessiRule__c> listOfRule = [
            SELECT Name, SIAE_LicenseConfig__c, SIAE_Order__c, SIAE_Attribute__c, SIAE_Operator__c,
                   SIAE_ValueFrom__c, SIAE_ValueTo__c, SIAE_DeviceType__c, SIAE_Action__c,
                   SIAE_ActionValue__c, SIAE_ApplyFromUnit__c, SIAE_ApplyToUnit__c, SIAE_Note__c, SIAE_AttributeTreshold__c, 
                   SIAE_AttributeQuantity__c, SIAE_AttributeQuantityList__c,SIAE_SecondaryAttribute__c, SIAE_RevenueItemDC__c, 
                   SIAE_DeviceGroupKey__c, SIAE_RevenueItemType__c, SIAE_IdInstrument__c,
                   SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
            FROM SIAE_DirittiConnessiRule__c
            WHERE SIAE_LicenseConfig__c IN :configNames
            ORDER BY SIAE_LicenseConfig__c, SIAE_Order__c ASC
        ];

        for (SIAE_DirittiConnessiRule__c rule : listOfRule) {
            if (!regoleByConfig.containsKey(rule.SIAE_LicenseConfig__c)) {
                regoleByConfig.put(rule.SIAE_LicenseConfig__c, new List<SIAE_DirittiConnessiRule__c>());
            }
            regoleByConfig.get(rule.SIAE_LicenseConfig__c).add(rule);
        }
        return regoleByConfig;
    }

    @TestVisible
    private static List<SIAE_DirittiConnessiRule__c> filterActiveRules(
        List<SIAE_DirittiConnessiRule__c> rules,
        Date effectiveDate
    ) {
        List<SIAE_DirittiConnessiRule__c> result = new List<SIAE_DirittiConnessiRule__c>();
        if (rules == null || effectiveDate == null) return result;

        for (SIAE_DirittiConnessiRule__c rule : rules) {
            Date validFrom = rule.SIAE_DataInizioValidita__c == null ? null : rule.SIAE_DataInizioValidita__c.dateGMT();
            Date validTo = rule.SIAE_DataFineValidita__c == null ? null : rule.SIAE_DataFineValidita__c.dateGMT();
            if ((validFrom == null || validFrom <= effectiveDate) &&
                (validTo == null || validTo >= effectiveDate)) {
                result.add(rule);
            }
        }
        return result;
    }

    @TestVisible
    private static List<SIAE_DirittiConnessiTariffa__c> filterActiveRates(
        List<SIAE_DirittiConnessiTariffa__c> rates,
        Date effectiveDate
    ) {
        List<SIAE_DirittiConnessiTariffa__c> result = new List<SIAE_DirittiConnessiTariffa__c>();
        if (rates == null || effectiveDate == null) return result;

        for (SIAE_DirittiConnessiTariffa__c rate : rates) {
            Date validFrom = rate.SIAE_DataInizioValidita__c == null ? null : rate.SIAE_DataInizioValidita__c.dateGMT();
            Date validTo = rate.SIAE_DataFineValidita__c == null ? null : rate.SIAE_DataFineValidita__c.dateGMT();
            if ((validFrom == null || validFrom <= effectiveDate) &&
                (validTo == null || validTo >= effectiveDate)) {
                result.add(rate);
            }
        }
        return result;
    }

    @TestVisible
    private static Map<Id, Map<String, String>> groupAttributes(List<OrderItemAttribute> attributes) {
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();

        if (attributes == null) {
            return result;
        }

        for (OrderItemAttribute attr : attributes) {
            Id itemId = attr.OrderItemId;
            String nomeAttributo = attr.AttributeDefinition.Code;
            String valoreAttributo = attr.AttributeValue; 

            if (itemId == null || String.isBlank(nomeAttributo)) {
                continue;
            }

            if (!result.containsKey(itemId)) {
                result.put(itemId, new Map<String, String>());
            }
            result.get(itemId).put(nomeAttributo, valoreAttributo);
        }

        return result;
    }
}