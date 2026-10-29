public class RCAContextReader {
    private RCAContextGateway gateway;

    public RCAContextReader(RCAContextGateway gateway) {
        this.gateway = gateway;
    }

    public RCASalesTransaction read(String contextId) {
        Map<String, Object> response = gateway.queryTags(new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{
                'SalesTransaction',
                'SalesTransactionItem',
                'SalesTransactionItemAttribute'
            }
        });
        return parse(safeMap(response.get('queryResult')));
    }

    @TestVisible
    private static RCASalesTransaction parse(Map<String, Object> queryRes) {
        RCASalesTransaction result = new RCASalesTransaction();
        Map<String, RCASalesTransaction.ItemNode> nodeByLineItemId = new Map<String, RCASalesTransaction.ItemNode>();
        parseTransactions(queryRes, result);
        parseItems(queryRes, result, nodeByLineItemId);
        parseAttributes(queryRes, nodeByLineItemId);
        return result;
    }

    private static void parseTransactions(Map<String, Object> queryRes, RCASalesTransaction result) {
        List<Object> rows = (List<Object>) queryRes.get('SalesTransaction');
        if (rows == null) return;
        for (Object raw : rows) {
            Map<String, Object> row = safeMap(raw);
            Map<String, Object> tagMap = safeMap(row.get('tagValue'));
            if (isNodeDeleted(tagMap)) continue;
            RCASalesTransaction.TransactionNode node = new RCASalesTransaction.TransactionNode();
            node.dataPath = (List<Object>) row.get('dataPath');
            node.transactionKey = getTransactionKey(node.dataPath);
            result.transactions.add(node);
        }
    }

    private static void parseItems(Map<String, Object> queryRes, RCASalesTransaction result, Map<String, RCASalesTransaction.ItemNode> byId) {
        List<Object> rows = (List<Object>) queryRes.get('SalesTransactionItem');
        if (rows == null) return;
        for (Object raw : rows) {
            Map<String, Object> row = safeMap(raw);
            Map<String, Object> tagMap = safeMap(row.get('tagValue'));
            if (isNodeDeleted(tagMap)) continue;
            RCASalesTransaction.ItemNode node = new RCASalesTransaction.ItemNode();
            node.dataPath = (List<Object>) row.get('dataPath');
            node.transactionKey = getTransactionKey(node.dataPath);
            node.lineItemId = getNodeField(tagMap, 'LineItem', 'tagValue');
            node.productId = getNodeField(tagMap, 'Product', 'tagValue');
            node.totalDA = defaultZero(getNodeFieldDecimal(tagMap, 'SIAE_TotalDA_I__c'));
            node.dirittiConnessi = defaultZero(getNodeFieldDecimal(tagMap, 'SIAE_DirittiConnessi_I__c'));
            node.totalTaxDA = defaultZero(getNodeFieldDecimal(tagMap, 'SIAE_TotalTaxDA__c'));
            node.totalTaxDC = defaultZero(getNodeFieldDecimal(tagMap, 'SIAE_TotalTaxDC__c'));
            node.derivedStartDateTime = RCAValueConverter.asDatetime(getNodeField(tagMap, 'DerivedStartDateTime__std', 'tagValue'));
            node.netTotalPrice = getNodeFieldDecimal(tagMap, 'ItemNetTotalPrice');
            node.commercialCode = getNodeField(tagMap, 'SIAE_CommercialAgreementCode__c', 'tagValue');
            node.typeOfFlatRate = getNodeField(tagMap, 'SIAE_TypeOfFlatRate__c', 'tagValue');
            node.typeCoverage = getNodeField(tagMap, 'SIAE_TypeOfCoverage__c', 'tagValue');
            node.flatAudioAmount = getNodeFieldDecimal(tagMap, 'SIAE_FlatAudio__c');
            node.flatVideoAmount = getNodeFieldDecimal(tagMap, 'SIAE_FlatVideo__c');
            node.periodicityCoefficient = getNodeFieldDecimal(tagMap, 'SIAE_CoeffStagionalita__c');
            node.coeffMaggiorazioneMQ = getNodeFieldDecimal(tagMap, 'SIAE_CoeffMaggiorazioneMQ__c');
            node.coeffAreeEsterne = getNodeFieldDecimal(tagMap, 'SIAE_CoeffAreeEsterne__c');
            node.lineItemPath = getNodeField(tagMap, 'LineItemPath', 'tagValue');
            node.dmlStatus = getItemDmlStatus(tagMap);
            node.effectiveFrom = safeMap(tagMap.get('EffectiveFrom')).get('tagValue');
            node.productSellingModel = getNodeField(tagMap, 'ProductSellingModel', 'tagValue');
            result.items.add(node);
            if (node.dataPath != null && node.dataPath.size() > 2) byId.put(String.valueOf(node.dataPath[2]), node);
        }
    }

    private static void parseAttributes(Map<String, Object> queryRes, Map<String, RCASalesTransaction.ItemNode> byId) {
        List<Object> rows = (List<Object>) queryRes.get('SalesTransactionItemAttribute');
        if (rows == null) return;
        List<AttributeHolder> holders = new List<AttributeHolder>();
        Set<Id> picklistIds = new Set<Id>();
        for (Object raw : rows) {
            Map<String, Object> row = safeMap(raw);
            List<Object> path = (List<Object>) row.get('dataPath');
            if (path == null || path.size() < 3) continue;
            Map<String, Object> tags = safeMap(row.get('tagValue'));
            if (isNodeDeleted(tags)) continue;
            String value = getNodeField(tags, 'AttributeValue', 'tagValue');
            String picklistId = getNodeField(tags, 'AttributePicklistValue', 'tagValue');
            if (String.isBlank(value) && String.isBlank(picklistId)) continue;
            AttributeHolder h = new AttributeHolder();
            h.dataPath = path;
            h.parentKey = String.valueOf(path[2]);
            h.parentLineItemId = getAttributeParentId(tags, h.parentKey);
            h.code = getNodeField(tags, 'AttributeDefinitionCode', 'tagValue');
            h.value = value;
            h.picklistId = picklistId;
            h.devicePrice = getNodeField(tags, 'SIAE_DevicePrice', 'tagValue');
            h.deviceTotalPrice = getNodeField(tags, 'SIAE_DeviceTotalPrice', 'tagValue');
            holders.add(h);
            if (String.isBlank(value) && String.isNotBlank(picklistId)) {
                try { picklistIds.add((Id) picklistId); } catch (Exception ignored) {}
            }
        }
        Map<Id, String> resolved = resolvePicklistValues(picklistIds);
        for (AttributeHolder h : holders) {
            String value = h.value;
            if (String.isBlank(value) && String.isNotBlank(h.picklistId)) {
                try { value = resolved.get((Id) h.picklistId); } catch (Exception ignored) {}
            }
            RCASalesTransaction.ItemNode parent = byId.get(h.parentKey);
            if (parent != null && String.isNotBlank(h.code) && String.isNotBlank(value)) {
                parent.attributeValueByCode.put(h.code, value);
                RCASalesTransaction.AttributeNode attribute = new RCASalesTransaction.AttributeNode();
                attribute.dataPath = h.dataPath;
                attribute.parentLineItemId = h.parentLineItemId;
                attribute.attributeCode = h.code;
                attribute.attributeValue = value;
                attribute.resolvedFromPicklist = String.isBlank(h.value);
                attribute.devicePrice = h.devicePrice;
                attribute.deviceTotalPrice = h.deviceTotalPrice;
                parent.attributes.add(attribute);
            }
        }
    }

    @TestVisible
    private static Map<Id, String> resolvePicklistValues(Set<Id> ids) {
        Map<Id, String> result = new Map<Id, String>();
        if (ids == null || ids.isEmpty()) return result;
        for (AttributePicklistValue value : [SELECT Id, Value FROM AttributePicklistValue WHERE Id IN :ids]) result.put(value.Id, value.Value);
        return result;
    }

    // dmlStatus of the line: LineItemPath first, then LineItem.
    private static String getItemDmlStatus(Map<String, Object> tags) {
        for (String tagName : new List<String>{ 'LineItemPath', 'LineItem' }) {
            Map<String, Object> tag = safeMap(tags.get(tagName));
            if (tag.containsKey('dmlStatus')) return RCAValueConverter.asString(tag.get('dmlStatus'));
        }
        return null;
    }

    // Parent line from SalesTransactionItemAttrParent; dataPath key when the tag is empty or an unresolved @{...} reference.
    private static String getAttributeParentId(Map<String, Object> tags, String pathParentKey) {
        String parentId = getNodeField(tags, 'SalesTransactionItemAttrParent', 'tagValue');
        Boolean unresolved = String.isBlank(parentId) || (parentId.startsWith('@{') && parentId.endsWith('}'));
        return unresolved ? pathParentKey : parentId;
    }

    private static Decimal defaultZero(Decimal value) { return value == null ? 0 : value; }
    private static Map<String, Object> safeMap(Object value) { return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>(); }
    private static String getTransactionKey(List<Object> path) { return path == null || path.size() < 2 || path[1] == null ? null : String.valueOf(path[1]); }
    private static Boolean isNodeDeleted(Map<String, Object> tags) { if (tags == null || tags.isEmpty()) return false; Map<String,Object> firstTag = safeMap(tags.values().iterator().next()); return 'DELETED'.equals(firstTag.get('dmlStatus')); }
    private static String getNodeField(Map<String, Object> source, String nodeName, String fieldName) { Map<String,Object> node = safeMap(source.get(nodeName)); Object value = node.get(fieldName); return value == null ? null : String.valueOf(value); }
    private static Decimal getNodeFieldDecimal(Map<String, Object> tags, String tagName) { if (tags == null || !tags.containsKey(tagName)) return null; return RCAValueConverter.asDecimal(safeMap(tags.get(tagName)).get('tagValue')); }

    private class AttributeHolder {
        List<Object> dataPath;
        String parentKey;
        String parentLineItemId;
        String code;
        String value;
        String picklistId;
        Object devicePrice;
        Object deviceTotalPrice;
    }
}