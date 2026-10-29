public class RCAContextWriter {
    private RCAContextGateway gateway;

    public RCAContextWriter(RCAContextGateway gateway) {
        this.gateway = gateway;
    }

    public static List<Map<String, Object>> buildUpdates(RCASalesTransaction salesTransaction) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        if (salesTransaction == null) return updates;
        for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
            for (RCASalesTransaction.AttributeNode attribute : item.attributes) addNodeUpdate(attribute.dataPath, attribute.attributeToUpdate, updates);
        }
        for (RCASalesTransaction.ItemNode item : salesTransaction.items) addNodeUpdate(item.dataPath, item.attributeToUpdate, updates);
        for (RCASalesTransaction.TransactionNode tx : salesTransaction.transactions) addNodeUpdate(tx.dataPath, tx.attributeToUpdate, updates);
        return updates;
    }

    public void write(String contextId, RCASalesTransaction salesTransaction) {
        List<Map<String, Object>> updates = RCAContextWriter.buildUpdates(salesTransaction);
        if (updates.isEmpty()) return;
        gateway.updateContextAttributes(new Map<String, Object>{
            'contextId' => contextId,
            'nodePathAndAttributes' => updates
        });
    }

    private static void addNodeUpdate(List<Object> originalPath, Map<String, Object> values, List<Map<String, Object>> updates) {
        List<Object> path = buildDataPathForUpdate(originalPath);
        List<Object> attributes = buildAttributes(values);
        if (path == null || attributes.isEmpty()) return;
        updates.add(new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => path },
            'attributes' => attributes
        });
    }

    private static List<Object> buildAttributes(Map<String, Object> values) {
        List<Object> result = new List<Object>();
        if (values == null) return result;
        for (String key : values.keySet()) result.add(new Map<String, Object>{ 'attributeName' => key, 'attributeValue' => values.get(key) });
        return result;
    }

    private static List<Object> buildDataPathForUpdate(List<Object> dataPath) {
        if (dataPath == null || dataPath.size() < 2) return null;
        List<Object> result = new List<Object>();
        for (Integer i = 1; i < dataPath.size(); i++) result.add(dataPath[i]);
        return result.isEmpty() ? null : result;
    }
}