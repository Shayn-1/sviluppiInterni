/**
 * Builds the canonical RCA model from the flat JSON returned by Salesforce Headless Pricing
 * (SalesTransaction[] -> SalesTransactionItem[] -> SalesTransactionItemAttribute[]).
 * dataPath holds the source indexes ([transaction], [transaction, item] or [transaction, item, attribute]) used by RCAJsonWriter.
 * Picklist attributes without AttributeValue are resolved from AttributePicklistValue
 * with a single query; the source JSON is never modified.
 */
public class RCAJsonReader {

    public static RCASalesTransaction read(Map<String, Object> root, String startDate) {
        RCASalesTransaction result = new RCASalesTransaction();
        Datetime fallbackStart = asStartDatetime(startDate);
        List<Object> transactions = asList(root == null ? null : root.get('SalesTransaction'));
        Map<Id, String> picklistValueById = resolvePicklistValues(transactions);
        for (Integer t = 0; t < transactions.size(); t++) {
            Map<String, Object> transactionMap = safeMap(transactions[t]);
            RCASalesTransaction.TransactionNode node = new RCASalesTransaction.TransactionNode();
            node.dataPath = new List<Object>{ t };
            node.transactionKey = String.valueOf(t);
            result.transactions.add(node);

            List<Object> items = asList(transactionMap.get('SalesTransactionItem'));
            for (Integer i = 0; i < items.size(); i++) {
                Map<String, Object> itemMap = safeMap(items[i]);
                if (isDeleted(itemMap)) continue;
                result.items.add(parseItem(itemMap, t, i, fallbackStart, picklistValueById));
            }
        }
        return result;
    }

    private static RCASalesTransaction.ItemNode parseItem(
        Map<String, Object> itemMap,
        Integer t,
        Integer i,
        Datetime fallbackStart,
        Map<Id, String> picklistValueById
    ) {
        RCASalesTransaction.ItemNode node = new RCASalesTransaction.ItemNode();
        node.dataPath = new List<Object>{ t, i };
        node.transactionKey = String.valueOf(t);
        node.lineItemId = RCAValueConverter.asString(itemMap.get('LineItem'));
        node.productId = RCAValueConverter.asString(itemMap.get('Product'));
        node.totalDA = defaultZero(RCAValueConverter.asDecimal(itemMap.get('SIAE_TotalDA_I__c')));
        node.dirittiConnessi = defaultZero(RCAValueConverter.asDecimal(itemMap.get('SIAE_DirittiConnessi_I__c')));
        node.totalTaxDA = defaultZero(RCAValueConverter.asDecimal(itemMap.get('SIAE_TotalTaxDA__c')));
        node.totalTaxDC = defaultZero(RCAValueConverter.asDecimal(itemMap.get('SIAE_TotalTaxDC__c')));
        Datetime derivedStart = RCAValueConverter.asDatetime(itemMap.get('DerivedStartDateTime__std'));
        node.derivedStartDateTime = derivedStart == null ? fallbackStart : derivedStart;
        node.typeCoverage = RCAValueConverter.asString(itemMap.get('SIAE_TypeOfCoverage__c'));
        parseAttributes(asList(itemMap.get('SalesTransactionItemAttribute')), node, picklistValueById);
        return node;
    }

    private static void parseAttributes(List<Object> attributes, RCASalesTransaction.ItemNode node, Map<Id, String> picklistValueById) {
        for (Integer a = 0; a < attributes.size(); a++) {
            Map<String, Object> attributeMap = safeMap(attributes[a]);
            String code = RCAValueConverter.asString(attributeMap.get('AttributeDefinitionCode'));
            String value = RCAValueConverter.asString(attributeMap.get('AttributeValue'));
            Boolean resolvedFromPicklist = String.isBlank(value);
            if (resolvedFromPicklist) {
                Id picklistId = asId(attributeMap.get('AttributePicklistValue'));
                value = picklistId == null ? null : picklistValueById.get(picklistId);
            }
            if (String.isBlank(code) || String.isBlank(value)) continue;
            node.attributeValueByCode.put(code, value);
            RCASalesTransaction.AttributeNode attribute = new RCASalesTransaction.AttributeNode();
            attribute.dataPath = new List<Object>{ node.dataPath[0], node.dataPath[1], a };
            attribute.attributeCode = code;
            attribute.attributeValue = value;
            attribute.resolvedFromPicklist = resolvedFromPicklist;
            node.attributes.add(attribute);
        }
    }

    private static Map<Id, String> resolvePicklistValues(List<Object> transactions) {
        Set<Id> picklistIds = new Set<Id>();
        for (Object transactionObj : transactions) {
            for (Object itemObj : asList(safeMap(transactionObj).get('SalesTransactionItem'))) {
                Map<String, Object> itemMap = safeMap(itemObj);
                if (isDeleted(itemMap)) continue;
                for (Object raw : asList(itemMap.get('SalesTransactionItemAttribute'))) {
                    Map<String, Object> attributeMap = safeMap(raw);
                    Id picklistId = asId(attributeMap.get('AttributePicklistValue'));
                    if (picklistId != null && String.isBlank(RCAValueConverter.asString(attributeMap.get('AttributeValue')))) {
                        picklistIds.add(picklistId);
                    }
                }
            }
        }
        Map<Id, String> result = new Map<Id, String>();
        if (picklistIds.isEmpty()) return result;
        for (AttributePicklistValue value : [SELECT Id, Value FROM AttributePicklistValue WHERE Id IN :picklistIds]) result.put(value.Id, value.Value);
        return result;
    }

    private static Datetime asStartDatetime(String startDate) {
        Datetime value = RCAValueConverter.asDatetime(startDate);
        if (value != null || String.isBlank(startDate)) return value;
        try { return Datetime.newInstanceGmt(Date.valueOf(startDate.trim()), Time.newInstance(0, 0, 0, 0)); } catch (Exception ignored) { return null; }
    }

    private static Boolean isDeleted(Map<String, Object> itemMap) { return 'DELETED'.equalsIgnoreCase(RCAValueConverter.asString(itemMap.get('dmlStatus'))); }
    private static Id asId(Object value) {
        String raw = RCAValueConverter.asString(value);
        if (String.isBlank(raw)) return null;
        try { return (Id) raw; } catch (Exception ignored) { return null; }
    }
    private static Decimal defaultZero(Decimal value) { return value == null ? 0 : value; }
    private static Map<String, Object> safeMap(Object value) { return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>(); }
    private static List<Object> asList(Object value) {
        if (value instanceof List<Object>) return (List<Object>) value;
        return value instanceof Map<String, Object> ? new List<Object>{ value } : new List<Object>();
    }
}