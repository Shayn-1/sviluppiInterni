@isTest
private class RCAContextReader_T {

    private static Map<String, Object> tag(Object value) {
        return new Map<String, Object>{ 'tagValue' => value };
    }

    private static Map<String, Object> queryResult(List<Object> items, List<Object> attributes) {
        return new Map<String, Object>{
            'SalesTransactionItem' => items,
            'SalesTransactionItemAttribute' => attributes
        };
    }

    @isTest
    static void parseReadsPreHookItemTags() {
        Map<String, Object> item = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'TX', 'LINE-1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'QLI-1', 'dmlStatus' => 'UPSERT' },
                'LineItemPath' => new Map<String, Object>{ 'tagValue' => 'QLI-1/child', 'dmlStatus' => 'UPSERT' },
                'EffectiveFrom' => tag('2026-11-15T00:00:00.000Z'),
                'ProductSellingModel' => tag('PSM-1')
            }
        };

        RCASalesTransaction.ItemNode node = RCAContextReader.parse(queryResult(new List<Object>{ item }, null)).items[0];

        System.assertEquals('QLI-1/child', node.lineItemPath);
        System.assertEquals('UPSERT', node.dmlStatus);
        System.assertEquals('2026-11-15T00:00:00.000Z', node.effectiveFrom);
        System.assertEquals('PSM-1', node.productSellingModel);
    }

    @isTest
    static void parseResolvesAttributeParentFromTagOrDataPath() {
        Map<String, Object> item = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'TX', 'LINE-1' },
            'tagValue' => new Map<String, Object>{ 'LineItem' => tag('QLI-1') }
        };
        Map<String, Object> taggedAttribute = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'TX', 'LINE-1', 'ATTR-1' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => tag('SIAE-ATTR-QTA'),
                'AttributeValue' => tag('650'),
                'SalesTransactionItemAttrParent' => tag('QLI-1')
            }
        };
        Map<String, Object> unresolvedAttribute = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'TX', 'LINE-1', 'ATTR-2' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => tag('SIAE-ATTR-LUOGO'),
                'AttributeValue' => tag('Solo a terra'),
                'SalesTransactionItemAttrParent' => tag('@{refLine.id}')
            }
        };

        List<RCASalesTransaction.AttributeNode> attributes = RCAContextReader.parse(
            queryResult(new List<Object>{ item }, new List<Object>{ taggedAttribute, unresolvedAttribute })
        ).items[0].attributes;

        System.assertEquals('QLI-1', attributes[0].parentLineItemId);
        System.assertEquals('LINE-1', attributes[1].parentLineItemId);
        System.assertEquals(new List<Object>{ 'CTX', 'TX', 'LINE-1', 'ATTR-2' }, attributes[1].dataPath);
        System.assertEquals(false, attributes[0].resolvedFromPicklist);
    }

    @isTest
    static void buildUpdatesWritesAttributeNodesBeforeItems() {
        RCASalesTransaction salesTransaction = new RCASalesTransaction();
        RCASalesTransaction.ItemNode item = new RCASalesTransaction.ItemNode();
        item.dataPath = new List<Object>{ 'CTX', 'TX', 'LINE-1' };
        item.attributeToUpdate.put('SIAE_CoeffStagionalita__c', '1');
        RCASalesTransaction.AttributeNode attribute = new RCASalesTransaction.AttributeNode();
        attribute.dataPath = new List<Object>{ 'CTX', 'TX', 'LINE-1', 'ATTR-1' };
        attribute.attributeToUpdate.put('AttributeValue', 'Non convenzionata');
        item.attributes.add(attribute);
        salesTransaction.items.add(item);

        List<Map<String, Object>> updates = RCAContextWriter.buildUpdates(salesTransaction);

        System.assertEquals(2, updates.size());
        Map<String, Object> attributePath = (Map<String, Object>) updates[0].get('nodePath');
        System.assertEquals(new List<Object>{ 'TX', 'LINE-1', 'ATTR-1' }, attributePath.get('dataPath'));
        Map<String, Object> itemPath = (Map<String, Object>) updates[1].get('nodePath');
        System.assertEquals(new List<Object>{ 'TX', 'LINE-1' }, itemPath.get('dataPath'));
    }
}