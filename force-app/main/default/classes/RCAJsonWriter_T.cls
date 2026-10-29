@isTest
private class RCAJsonWriter_T {

    private static Map<String, Object> parse(String body) {
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static Map<String, Object> transactionAt(Map<String, Object> root, Integer t) {
        return (Map<String, Object>) ((List<Object>) root.get('SalesTransaction'))[t];
    }

    private static Map<String, Object> itemAt(Map<String, Object> root, Integer t, Integer i) {
        return (Map<String, Object>) ((List<Object>) transactionAt(root, t).get('SalesTransactionItem'))[i];
    }

    @isTest
    static void applyWritesItemAndTransactionValuesOnSourceNodes() {
        Map<String, Object> root = parse('{"SalesTransaction": ['
            + '{"SalesTransactionItem": [{"LineItem": "A"}]},'
            + '{"SalesTransactionItem": [{"LineItem": "B", "dmlStatus": "DELETED"}, {"LineItem": "C"}]}]}');
        RCASalesTransaction salesTransaction = RCAJsonReader.read(root, '2026-01-01');
        salesTransaction.items[1].attributeToUpdate.put('TotalLineAmount', 55);
        salesTransaction.items[1].attributeToUpdate.put('SIAE_PaymentItems__c', '{"paymentItems":[]}');
        salesTransaction.transactions[1].attributeToUpdate.put('SIAE_PriceDetails__c', '{"lineItems":[]}');

        RCAJsonWriter.apply(root, salesTransaction);

        System.assertEquals(55, itemAt(root, 1, 1).get('TotalLineAmount'));
        System.assertEquals('{"paymentItems":[]}', itemAt(root, 1, 1).get('SIAE_PaymentItems__c'));
        System.assertEquals('{"lineItems":[]}', transactionAt(root, 1).get('SIAE_PriceDetails__c'));
        System.assertEquals(false, itemAt(root, 1, 0).containsKey('TotalLineAmount'), 'La riga DELETED non va modificata');
        System.assertEquals(false, itemAt(root, 0, 0).containsKey('TotalLineAmount'));
        System.assertEquals(false, transactionAt(root, 0).containsKey('SIAE_PriceDetails__c'));
    }

    @isTest
    static void applyWritesAttributeValuesOnSourceAttributeNodes() {
        Map<String, Object> root = parse('{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "A",'
            + '"SalesTransactionItemAttribute": [{"AttributeDefinitionCode": "X", "AttributeValue": ""},'
            + '{"AttributeDefinitionCode": "Y", "AttributeValue": "1"}]}]}]}');
        RCASalesTransaction salesTransaction = RCAJsonReader.read(root, '2026-01-01');
        salesTransaction.items[0].attributes[0].attributeToUpdate.put('AttributeValue', 'Risolto');

        RCAJsonWriter.apply(root, salesTransaction);

        List<Object> attributes = (List<Object>) itemAt(root, 0, 0).get('SalesTransactionItemAttribute');
        System.assertEquals('', ((Map<String, Object>) attributes[0]).get('AttributeValue'));
        System.assertEquals('Risolto', ((Map<String, Object>) attributes[1]).get('AttributeValue'));
    }

    @isTest
    static void applyIgnoresNodesWithInvalidDataPath() {
        Map<String, Object> root = parse('{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "A"}]}]}');
        RCASalesTransaction salesTransaction = new RCASalesTransaction();
        RCASalesTransaction.ItemNode outOfRange = new RCASalesTransaction.ItemNode();
        outOfRange.dataPath = new List<Object>{ 0, 5 };
        outOfRange.attributeToUpdate.put('TotalLineAmount', 1);
        RCASalesTransaction.ItemNode withoutPath = new RCASalesTransaction.ItemNode();
        withoutPath.attributeToUpdate.put('TotalLineAmount', 2);
        salesTransaction.items.add(outOfRange);
        salesTransaction.items.add(withoutPath);

        RCAJsonWriter.apply(root, salesTransaction);
        RCAJsonWriter.apply(root, null);

        System.assertEquals(false, itemAt(root, 0, 0).containsKey('TotalLineAmount'));
    }
}