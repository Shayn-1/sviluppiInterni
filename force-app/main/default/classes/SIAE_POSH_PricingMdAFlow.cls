/**
 * @description       : Classe Apex invocabile da AutoLaunched Flow.
 * Funge da Post-Hook per il calcolo del Pricing. Riceve il JSON in output
 * dal motore Headless Pricing, filtra i campi restituiti e applica i
 * coefficienti di stagionalità su SIAE_PrezzoSemestrale__c e
 * SIAE_PrezzoTrimestrale__c in base ai mesi residui dell'anno solare.
 *
 * @author            : Gaetano Iuliano
 * @group             : NTT Data - SIAE
**/
public class SIAE_POSH_PricingMdAFlow {

    private static final String DEBUG_VERSION = 'SIAE_POST_Pricing_V1';
    private static final String FIELD_COEFF_AREE_EST = 'SIAE_CoeffAreeEsterne__c';

    // Campi da mantenere per ogni SalesTransactionItem
    private static final Set<String> ITEM_FIELDS_TO_KEEP = new Set<String>{
        'SIAE_PrezzoTrimestrale__c',
        'SIAE_FlatAudio__c',
        'LineItem',
        'TotalLineAmount',
        'NetUnitPrice',
        'SIAE_FlatVideo__c',
        'ItemProductCode',
        'Product',
        'SIAE_PrezzoSemestrale__c',
        'LineItemQuantity',
        'SIAE_FlatVideoSemestrale__c',
        'SIAE_FlatVideoTrimestrale__c',
        'SIAE_FlatAudioSemestrale__c',
        'SIAE_FlatAudioTrimestrale__c'
    };

    // Campi da mantenere per ogni SalesTransaction (root level)
    private static final Set<String> ST_FIELDS_TO_KEEP = new Set<String>{
        'SalesTransactionItem',
        'TotalAmount',
        'HeaderDiscountValue',
        'Subtotal',
        'PriceBooks'
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
            description = 'JSON filtrato con coefficienti di stagionalità applicati'
        )
        public String finalJsonString;

        @InvocableVariable(label='Esito elaborazione')
        public String status;

        @InvocableVariable(label='Messaggio di dettaglio')
        public String message;
    }

    @InvocableMethod(
        label       = 'SIAE - Pricing Post-Hook'
        description = 'Filtra i campi del JSON di output e applica i coefficienti di stagionalità su prezzi semestrale e trimestrale'
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

        try {
            System.debug('Test-->' + jsonString);
            if (String.isBlank(jsonString)) {
                output.status          = 'ERROR';
                output.message         = 'Input JSON vuoto o nullo.';
                output.finalJsonString = jsonString;
                return output;
            }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonString);

            // Il JSON in ingresso ha SalesTransaction direttamente sulla radice
            List<Object> salesTransactionList = getAsList(root.get('SalesTransaction'));

            // ── Calcolo mesi residui anno solare ──────────────────────────────────────
            Integer mesiResiduiFallback = SIAE_UTIL_PricingMdA.calcMesiResidui(startDate);

            // ── Raccolta Product Id per query configurazioni ───────────────────────────
            Set<Id> productIds = new Set<Id>();
            for (Object stObj : salesTransactionList) {
                Map<String, Object> st       = (Map<String, Object>) stObj;
                List<Object>        itemList = getAsList(st.get('SalesTransactionItem'));
                for (Object itemObj : itemList) {
                    Map<String, Object> item = (Map<String, Object>) itemObj;
                    String productIdStr = (String) item.get('Product');
                    if (String.isNotBlank(productIdStr)) {
                        try { productIds.add((Id) productIdStr); } catch (Exception e) {}
                    }
                }
            }

            MdAPricingConfiguration.ConfigurationIndex pricingConfigurations =
                MdAPricingConfiguration.load(productIds);

            // ── Elaborazione item: filtro campi + coefficienti stagionalità ────────────
            List<Object> filteredSalesTxList = new List<Object>();

            for (Object stObj : salesTransactionList) {
                Map<String, Object> st       = (Map<String, Object>) stObj;
                List<Object>        itemList = getAsList(st.get('SalesTransactionItem'));

                List<Object> filteredItems = new List<Object>();
                for (Object itemObj : itemList) {
                    Map<String, Object> item        = (Map<String, Object>) itemObj;
                    Map<String, Object> filteredItem = filterMap(item, ITEM_FIELDS_TO_KEEP);

                    // Recupero configurazione prodotto
                    String productIdStr = (String) item.get('Product');
                    Datetime itemEffectiveFrom = resolveItemEffectiveFrom(item, startDate);
                    Integer mesiResidui = itemEffectiveFrom == null
                        ? mesiResiduiFallback
                        : SIAE_UTIL_PricingMdA.calcMesiResidui(String.valueOf(itemEffectiveFrom.date()));

                    SIAE_ConfigurazionePricing__c conf = null;
                    if (String.isNotBlank(productIdStr)) {
                        try {
                            Date itemEffectiveDate = resolveItemEffectiveDate(item, startDate);
                            conf = pricingConfigurations.resolve((Id) productIdStr, itemEffectiveDate);
                        } catch (Exception e) {}
                    }

                    SIAE_UTIL_PricingMdA.resolvePicklistAttributeValues(
                        getAsList(item.get('SalesTransactionItemAttribute'))
                    );

                    // Applica coefficiente stagionalità su NetUnitPrice (pro-rata anno solare)
                    SIAE_UTIL_PricingMdA.applyAnnualProRata(filteredItem, 'NetUnitPrice', mesiResidui, conf);

                    // Prezzo semestrale: con coeff se mesi residui >= 6, altrimenti 0
                    if (mesiResidui >= 6) {
                        if (conf != null && conf.SIAE_CoeffStag_Semestrale__c != null) {
                            SIAE_UTIL_PricingMdA.applyCoeff(filteredItem, 'SIAE_PrezzoSemestrale__c', conf.SIAE_CoeffStag_Semestrale__c);
                        }
                    } else {
                        filteredItem.put('SIAE_PrezzoSemestrale__c', 0);
                    }

                    // Prezzo trimestrale: 0 se mesi residui < 3, altrimenti applica coeff
                    if (mesiResidui < 3) {
                        filteredItem.put('SIAE_PrezzoTrimestrale__c', 0);
                    } else if (conf != null && conf.SIAE_CoeffStag_Trimestrale__c != null) {
                        SIAE_UTIL_PricingMdA.applyCoeff(filteredItem, 'SIAE_PrezzoTrimestrale__c', conf.SIAE_CoeffStag_Trimestrale__c);
                    }
                    
                    // Flat base + flat stagionali audio/video, con maggiorazione aree esterne
                    Decimal coeffAreeEsterne = SIAE_UTIL_PricingMdA.parseDecimal(String.valueOf(item.get(FIELD_COEFF_AREE_EST)));
                    SIAE_UTIL_PricingMdA.applyFlatAmounts(
                        item,
                        filteredItem,
                        conf,
                        mesiResidui,
                        coeffAreeEsterne
                    );

                    filteredItems.add(filteredItem);
                }

                Map<String, Object> filteredSt = filterMap(st, ST_FIELDS_TO_KEEP);
                filteredSt.put('SalesTransactionItem', filteredItems);
                filteredSalesTxList.add(filteredSt);
            }

            // ── Ricostruzione struttura output (stessa struttura dell'input) ─────────
            Map<String, Object> outputRoot = new Map<String, Object>{
                'SalesTransaction' => filteredSalesTxList 
            };

            output.finalJsonString = JSON.serialize(outputRoot);
            output.status          = 'SUCCESS';
            output.message         = 'Elaborazione completata.';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, DEBUG_VERSION + ' ERRORE: ' + e.getMessage() + '\n' + e.getStackTraceString());
            output.status          = 'ERROR';
            output.message         = 'Errore durante l\'elaborazione: ' + e.getMessage();
            output.finalJsonString = jsonString;
        }

        return output;
    }

    // =========================================================================
    // HELPER METHODS
    // =========================================================================

    /**
     * Restituisce una nuova mappa contenente solo le chiavi presenti in keysToKeep.
     */
    private static Map<String, Object> filterMap(Map<String, Object> source, Set<String> keysToKeep) {
        Map<String, Object> result = new Map<String, Object>();
        for (String key : keysToKeep) {
            if (source.containsKey(key)) {
                result.put(key, source.get(key));
            }
        }
        return result;
    }

    /**
     * Lettura sicura di un nodo JSON che può essere List o singolo oggetto.
     */
    private static List<Object> getAsList(Object node) {
        List<Object> result = new List<Object>();
        if (node == null) return result;
        if (node instanceof List<Object>) {
            result = (List<Object>) node;
        } else if (node instanceof Map<String, Object>) {
            result.add(node);
        }
        return result;
    }

    private static Date resolveItemEffectiveDate(Map<String, Object> item, String fallbackStartDate) {
        if (item != null) {
            for (String fieldName : new List<String>{ 'EffectiveFrom', 'StartDate', 'DerivedStartDateTime__std' }) {
                Date parsed = RCAValueConverter.asDate(item.get(fieldName));
                if (parsed != null) { return parsed; }
            }
        }
        return RCAValueConverter.asDate(fallbackStartDate);
    }

    private static Datetime resolveItemEffectiveFrom(Map<String, Object> item, String fallbackStartDate) {
        if (item != null) {
            for (String fieldName : new List<String>{ 'DerivedStartDateTime__std', 'EffectiveFrom', 'StartDate' }) {
                Object raw = item.get(fieldName);
                Datetime parsed = parseDatetime(raw);
                if (parsed != null) { return parsed; }
            }
        }
        return parseDatetime(fallbackStartDate);
    }

    private static Datetime parseDatetime(Object raw) {
        if (raw == null) { return null; }
        if (raw instanceof Datetime) { return (Datetime)raw; }
        String value = String.valueOf(raw);
        if (String.isBlank(value)) { return null; }
        try { return (Datetime)JSON.deserialize('"' + value + '"', Datetime.class); } catch (Exception e) {}
        try { return Datetime.newInstance(Date.valueOf(value.substring(0, 10)), Time.newInstance(0, 0, 0, 0)); } catch (Exception e) {}
        return null;
    }
}