/**
 * @description       : Classe Apex invocabile da AutoLaunched Flow.
 * Post-Hook TTPP del pricing headless: applica TTPPPricingProcessor al JSON
 * in output dal motore Headless Pricing, calcola i totali di testata (DAP inclusi)
 * e restituisce i soli campi del contratto TTPP.
 *
 * @author            : Domenico Del Prete
 * @group             : NTT Data - SIAE
**/
public class SIAE_POSH_PricingTTPPFlow {

    private static final String DEBUG_VERSION = 'SIAE_POST_PricingTTPP_V1';
    private static final String FIELD_PRICE_DETAILS = 'SIAE_PriceDetails__c';
    private static final String FIELD_TOTAL_LINE_AMOUNT = 'TotalLineAmount';

    // Campi da mantenere per ogni SalesTransactionItem
    private static final Set<String> ITEM_FIELDS_TO_KEEP = new Set<String>{
        'LineItem',
        'Product',
        'ItemProductCode',
        'LineItemQuantity',
        'NetUnitPrice',
        'TotalLineAmount',
        'SIAE_TotalDA__c',
        'SIAE_DirittiConnessi__c'
    };

    // Campi da mantenere per ogni SalesTransaction (root level)
    private static final Set<String> ST_FIELDS_TO_KEEP = new Set<String>{
        'PriceBooks',
        'TotalAmount',
        'Subtotal',
        FIELD_PRICE_DETAILS,
        'SalesTransactionItem'
    };

    public class FlowInput {
        @InvocableVariable(
            label       = 'JSON Pricing Result (input)'
            description = 'JSON generato dal motore Headless Pricing'
            required    = true
        )
        public String pricingResultJson;

        @InvocableVariable(
            label       = 'Data inizio copertura'
            required    = true
        )
        public String startDate;
    }

    public class FlowOutput {
        @InvocableVariable(
            label       = 'JSON elaborato (output)'
            description = 'JSON TTPP con DC, DAP e dettaglio pagamento'
        )
        public String finalJsonString;

        @InvocableVariable(label='Esito elaborazione')
        public String status;

        @InvocableVariable(label='Messaggio di dettaglio')
        public String message;
    }

    @InvocableMethod(
        label       = 'SIAE - Pricing Post-Hook TTPP'
        description = 'Applica il pricing TTPP (DDA, DC, DAP, payment items) al JSON del pricing headless'
        category    = 'SIAE Pricing'
    )
    public static List<FlowOutput> execute(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        for (FlowInput inp : inputs) {
            outputs.add(processJson(inp.pricingResultJson, inp.startDate));
        }
        return outputs;
    }

    private static FlowOutput processJson(String jsonString, String startDate) {
        FlowOutput output = new FlowOutput();
        output.finalJsonString = jsonString;
        if (String.isBlank(jsonString)) {
            output.status  = 'ERROR';
            output.message = 'Input JSON vuoto o nullo.';
            return output;
        }

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
            RCASalesTransaction salesTransaction = RCAJsonReader.read(root, startDate);
            TTPPPricingProcessor.process(salesTransaction);
            RCAJsonWriter.apply(root, salesTransaction);

            output.finalJsonString = JSON.serialize(finalizeOutput(root));
            output.status          = 'SUCCESS';
            output.message         = 'Pricing TTPP applicato.';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, DEBUG_VERSION + ' ERRORE: ' + e.getMessage() + '\n' + e.getStackTraceString());
            output.status  = 'ERROR';
            output.message = e.getMessage();
        }
        return output;
    }

    /**
     * Totali di testata (somma dei TotalLineAmount, DAP inclusi), campi JSON da stringa a oggetto
     * e filtro sui campi del contratto TTPP.
     */
    @TestVisible
    private static Map<String, Object> finalizeOutput(Map<String, Object> root) {
        List<Object> filteredSalesTxList = new List<Object>();
        for (Object stObj : getAsList(root.get('SalesTransaction'))) {
            Map<String, Object> st = (Map<String, Object>) stObj;
            List<Object> filteredItems = new List<Object>();
            Decimal total = 0;
            for (Object itemObj : getAsList(st.get('SalesTransactionItem'))) {
                Map<String, Object> filteredItem = filterMap((Map<String, Object>) itemObj, ITEM_FIELDS_TO_KEEP);
                Decimal lineAmount = RCAValueConverter.asDecimal(filteredItem.get(FIELD_TOTAL_LINE_AMOUNT));
                total += lineAmount == null ? 0 : lineAmount;
                filteredItems.add(filteredItem);
            }

            Map<String, Object> filteredSt = filterMap(st, ST_FIELDS_TO_KEEP);
            deserializeField(filteredSt, FIELD_PRICE_DETAILS);
            filteredSt.put('TotalAmount', RCAValueConverter.roundMoney(total));
            filteredSt.put('Subtotal', RCAValueConverter.roundMoney(total));
            filteredSt.put('SalesTransactionItem', filteredItems);
            filteredSalesTxList.add(filteredSt);
        }
        return new Map<String, Object>{ 'SalesTransaction' => filteredSalesTxList };
    }

    // =========================================================================
    // HELPER METHODS
    // =========================================================================

    private static void deserializeField(Map<String, Object> node, String key) {
        Object value = node.get(key);
        if (value instanceof String && String.isNotBlank((String) value)) {
            node.put(key, JSON.deserializeUntyped((String) value));
        }
    }

    private static Map<String, Object> filterMap(Map<String, Object> source, Set<String> keysToKeep) {
        Map<String, Object> result = new Map<String, Object>();
        for (String key : keysToKeep) {
            if (source.containsKey(key)) {
                result.put(key, source.get(key));
            }
        }
        return result;
    }

    private static List<Object> getAsList(Object node) {
        if (node instanceof List<Object>) return (List<Object>) node;
        return node instanceof Map<String, Object> ? new List<Object>{ node } : new List<Object>();
    }
}