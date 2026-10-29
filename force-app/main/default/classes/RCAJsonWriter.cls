/**
 * Writes RCA attributeToUpdate values (transactions, items, item attributes) back on the flat Headless Pricing JSON.
 * Nodes are located through the source indexes stored in dataPath by RCAJsonReader.
 */
public class RCAJsonWriter {

    public static void apply(Map<String, Object> root, RCASalesTransaction salesTransaction) {
        if (root == null || salesTransaction == null) return;
        List<Object> transactions = asList(root.get('SalesTransaction'));
        for (RCASalesTransaction.TransactionNode tx : salesTransaction.transactions) putAll(findNode(transactions, tx.dataPath), tx.attributeToUpdate);
        for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
            putAll(findNode(transactions, item.dataPath), item.attributeToUpdate);
            for (RCASalesTransaction.AttributeNode attribute : item.attributes) putAll(findNode(transactions, attribute.dataPath), attribute.attributeToUpdate);
        }
    }

    private static Map<String, Object> findNode(List<Object> transactions, List<Object> dataPath) {
        if (dataPath == null || dataPath.isEmpty()) return null;
        Map<String, Object> node = elementAt(transactions, dataPath[0]);
        if (node == null || dataPath.size() == 1) return node;
        node = elementAt(asList(node.get('SalesTransactionItem')), dataPath[1]);
        if (node == null || dataPath.size() == 2) return node;
        return elementAt(asList(node.get('SalesTransactionItemAttribute')), dataPath[2]);
    }

    private static Map<String, Object> elementAt(List<Object> values, Object index) {
        Integer i = index instanceof Integer ? (Integer) index : null;
        if (i == null || i < 0 || i >= values.size()) return null;
        return values[i] instanceof Map<String, Object> ? (Map<String, Object>) values[i] : null;
    }

    private static void putAll(Map<String, Object> node, Map<String, Object> values) {
        if (node != null && values != null) node.putAll(values);
    }

    private static List<Object> asList(Object value) {
        if (value instanceof List<Object>) return (List<Object>) value;
        return value instanceof Map<String, Object> ? new List<Object>{ value } : new List<Object>();
    }
}