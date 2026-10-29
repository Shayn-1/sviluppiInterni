@isTest
private class RCAJsonReader_T {

    private static Map<String, Object> parse(String body) {
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    @isTest
    static void readMapsItemFieldsAndAttributes() {
        Map<String, Object> root = parse('{"SalesTransaction": [{"PriceBooks": "PB1", "SalesTransactionItem": [{'
            + '"LineItem": "LI1", "Product": "P1", "SIAE_TotalDA_I__c": 120.5, "SIAE_DirittiConnessi_I__c": "30",'
            + '"SIAE_TotalTaxDA__c": 10, "SIAE_TotalTaxDC__c": 2,'
            + '"DerivedStartDateTime__std": "2026-11-15T20:00:00.000Z",'
            + '"SalesTransactionItemAttribute": ['
            + '{"AttributeDefinitionCode": "SIAE-ATTR-FP-BALLO", "AttributeValue": "true"},'
            + '{"AttributeDefinitionCode": "SIAE-ATTR-FP-MUS-VIVO", "AttributeValue": ""}]}]}]}');

        RCASalesTransaction result = RCAJsonReader.read(root, '2026-01-01');

        System.assertEquals(1, result.transactions.size());
        System.assertEquals(1, result.items.size());
        RCASalesTransaction.ItemNode item = result.items[0];
        System.assertEquals('LI1', item.lineItemId);
        System.assertEquals('P1', item.productId);
        System.assertEquals(120.5, item.totalDA);
        System.assertEquals(30, item.dirittiConnessi);
        System.assertEquals(10, item.totalTaxDA);
        System.assertEquals(2, item.totalTaxDC);
        System.assertEquals(Datetime.newInstanceGmt(2026, 11, 15, 20, 0, 0), item.derivedStartDateTime);
        System.assertEquals(new Map<String, String>{ 'SIAE-ATTR-FP-BALLO' => 'true' }, item.attributeValueByCode);
        System.assertEquals(1, item.attributes.size());
        System.assertEquals('SIAE-ATTR-FP-BALLO', item.attributes[0].attributeCode);
    }

    @isTest
    static void readDefaultsMissingAmountsToZeroAndFallsBackToStartDate() {
        Map<String, Object> root = parse('{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "LI1"}]}]}');

        RCASalesTransaction.ItemNode item = RCAJsonReader.read(root, '2026-03-10').items[0];

        System.assertEquals(0, item.totalDA);
        System.assertEquals(0, item.dirittiConnessi);
        System.assertEquals(0, item.totalTaxDA);
        System.assertEquals(0, item.totalTaxDC);
        System.assertEquals(Date.newInstance(2026, 3, 10), item.derivedStartDateTime.dateGmt());
    }

    @isTest
    static void readSkipsDeletedItemsAndKeepsSourceIndexesInDataPath() {
        Map<String, Object> root = parse('{"SalesTransaction": ['
            + '{"SalesTransactionItem": [{"LineItem": "A"}]},'
            + '{"SalesTransactionItem": [{"LineItem": "B", "dmlStatus": "DELETED"}, {"LineItem": "C"}]}]}');

        RCASalesTransaction result = RCAJsonReader.read(root, '2026-01-01');

        System.assertEquals(2, result.transactions.size());
        System.assertEquals('1', result.transactions[1].transactionKey);
        System.assertEquals(new List<Object>{ 1 }, result.transactions[1].dataPath);
        System.assertEquals(2, result.items.size());
        RCASalesTransaction.ItemNode itemC = result.items[1];
        System.assertEquals('C', itemC.lineItemId);
        System.assertEquals('1', itemC.transactionKey);
        System.assertEquals(new List<Object>{ 1, 1 }, itemC.dataPath);
    }

    @isTest
    static void readAcceptsSingleSalesTransactionObject() {
        Map<String, Object> root = parse('{"SalesTransaction": {"SalesTransactionItem": {"LineItem": "A"}}}');

        RCASalesTransaction result = RCAJsonReader.read(root, '2026-01-01');

        System.assertEquals(1, result.transactions.size());
        System.assertEquals(1, result.items.size());
        System.assertEquals('A', result.items[0].lineItemId);
    }

    @isTest
    static void readResolvesPicklistAttributesWithoutChangingSourceJson() {
        AttributePicklist picklist = new AttributePicklist(Name = 'Test Genere Evento');
        insert picklist;
        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Ballo', PicklistId = picklist.Id, Code = 'BALLO-TEST', Value = 'Ballo'
        );
        insert pv;

        Map<String, Object> root = parse('{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "LI1",'
            + '"SalesTransactionItemAttribute": ['
            + '{"AttributeDefinitionCode": "SIAE-ATTR-FP-GENERE", "AttributePicklistValue": "' + pv.Id + '"},'
            + '{"AttributeDefinitionCode": "SIAE-ATTR-FP-FAKE", "AttributePicklistValue": "not-an-id"}]}]}]}');

        RCASalesTransaction.ItemNode item = RCAJsonReader.read(root, '2026-01-01').items[0];

        System.assertEquals(new Map<String, String>{ 'SIAE-ATTR-FP-GENERE' => 'Ballo' }, item.attributeValueByCode);
        System.assertEquals('Ballo', item.attributes[0].attributeValue);
        Map<String, Object> sourceItem = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) ((List<Object>) root.get('SalesTransaction'))[0]).get('SalesTransactionItem'))[0];
        Map<String, Object> sourceAttribute = (Map<String, Object>) ((List<Object>) sourceItem.get('SalesTransactionItemAttribute'))[0];
        System.assertEquals(false, sourceAttribute.containsKey('AttributeValue'), 'Il reader non deve modificare il JSON sorgente.');
        System.assertEquals(true, item.attributes[0].resolvedFromPicklist);
    }

    @isTest
    static void readKeepsTypeOfCoverageAndAttributeSourceIndexes() {
        Map<String, Object> root = parse('{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "LI1",'
            + '"SIAE_TypeOfCoverage__c": "Annuale", "SalesTransactionItemAttribute": ['
            + '{"AttributeDefinitionCode": "SIAE-ATTR-VUOTO", "AttributeValue": ""},'
            + '{"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "650"}]}]}]}');

        RCASalesTransaction.ItemNode item = RCAJsonReader.read(root, '2026-01-01').items[0];

        System.assertEquals('Annuale', item.typeCoverage);
        System.assertEquals(1, item.attributes.size());
        System.assertEquals(new List<Object>{ 0, 0, 1 }, item.attributes[0].dataPath);
        System.assertEquals(false, item.attributes[0].resolvedFromPicklist);
    }
}