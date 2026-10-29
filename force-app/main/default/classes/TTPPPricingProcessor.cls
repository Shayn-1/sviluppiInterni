/**
 * Domain processor for TTPP pricing.
 * Contains catalog-specific pricing rules and mutates the canonical RCA transaction model.
 * It does not read from or write to IndustriesContext and does not depend on RevSignaling.
 */
public class TTPPPricingProcessor {
     /* ========================= CONFIG ========================= */

    private static final String DECISION_TABLE_API_NAME = 'SIAE_DT_TTPP_GenereEvento_Default';

    // Input della Decision Table.
    private static final String DT_INPUT_MUSICA_DAL_VIVO = 'SIAE_MusicaDalVivo__c';
    private static final String DT_INPUT_MUSICA_REGISTRATA = 'SIAE_MusicaRegistrata__c';
    private static final String DT_INPUT_BALLO = 'SIAE_Ballo__c';
    private static final String DT_INPUT_DATAINIZIOVALIDITA = 'SIAE_DataInizioValidita__c';
    private static final String DT_INPUT_DATAFINEVALIDITA = 'SIAE_DataFineValidita__c';

    // Output della Decision Table.
    private static final String DT_OUTPUT_GENERE = 'SIAE_GenereEvento__c';
    private static final String DT_OUTPUT_PERCENTUALE = 'SIAE_PercentualeIncidenza__c';
    private static final String DT_OUTPUT_VOCE_INCASSO_DDA = 'SIAE_VoceIncassoDDA__c';
    private static final String DT_OUTPUT_VOCE_INCASSO_DC = 'SIAE_VoceIncassoDC__c';

    // Attributi catalogo Feste Private.
    private static final String ATTR_MUSICA_DAL_VIVO = 'SIAE-ATTR-FP-MUS-VIVO';
    private static final String ATTR_MUSICA_REGISTRATA = 'SIAE-ATTR-FP-MUS-REG';
    private static final String ATTR_BALLO = 'SIAE-ATTR-FP-BALLO';

    // Campi JSON da creare/verificare su QuoteLineItem e Quote.
    // E' possibile usare lo stesso API name sui due oggetti.
    private static final String FIELD_TTPP_FE_DETAIL_JSON = 'SIAE_PriceDetails__c';

    // DC gia calcolato dalla Pricing Procedure: la POSH non ricalcola eligibility o importo.
    private static final String CONTEXT_DIRITTI_CONNESSI = 'SIAE_DirittiConnessi_I__c';
    private static final String FIELD_DIRITTI_CONNESSI = 'SIAE_DirittiConnessi__c';
    private static final String FIELD_TOTAL_TAX_DA = 'SIAE_TotalTaxDA__c';
    private static final String FIELD_TOTAL_TAX_DC = 'SIAE_TotalTaxDC__c';

    // Campi pricing/context.
    private static final String CONTEXT_TOTAL_DA = 'SIAE_TotalDA_I__c';
    private static final String FIELD_TOTAL_DA = 'SIAE_TotalDA__c';
    private static final String FIELD_NET_TOTAL_PRICE = 'NetTotalPrice';
    private static final String FIELD_NET_UNIT_PRICE = 'NetUnitPrice';
    private static final String FIELD_TOTAL_LINE_AMOUNT = 'TotalLineAmount';
    private static final String FIELD_UNIT_PRICE = 'UnitPrice';
    private static final String FIELD_SUBTOTAL = 'Subtotal';
    private static final String FIELD_TOTAL_AMOUNT = 'TotalAmount';
    private static final String FIELD_PAYMENT_ITEMS = 'SIAE_PaymentItems__c';

    // DAP / spese istruttoria: importi fissi, NON splittati per genere.
    private static final Decimal DAP_DDA_AMOUNT = 4;
    private static final Decimal DAP_DC_AMOUNT = 1;
    private static final String PAYMENT_TYPE_DDA = 'DDA';
    private static final String PAYMENT_TYPE_DC = 'DC';
    private static final String PAYMENT_TYPE_DAP_DDA = 'SI_DDA';
    private static final String PAYMENT_TYPE_DAP_DC = 'SI_DC';

    // TODO: valorizzare con le voci/codici esposti al CMS per tooltip DAP/IVA.
    private static final String ITEM_CODE_DAP_DDA = '3760';
    private static final String ITEM_CODE_DAP_DC = '3760';
    private static final String ITEM_CODE_IVA_DDA = 'IVA_DDA';
    private static final String ITEM_CODE_IVA_DC = 'IVA_DC';

    /* ========================= DTO ========================= */

    public class EventRuleResult {
        public String genereEvento;
        public Decimal percentualeIncidenza;
        public String voceIncassoDDA;
        public String voceIncassoDC;
    }

    public class VoceIncassoDetail {
        public String voceIncasso;
        public String tipoCosto;
        public Decimal importoFinale;
    }

    public class CompensoDetail {
        public String genereEvento;
        public Decimal percentualeIncidenza;
        public List<VoceIncassoDetail> vociIncasso = new List<VoceIncassoDetail>();
    }

    public class DirittiConnessiDetail {
        public String voceIncasso;
        public String tipoCosto = 'DC';
        public Decimal importoFinale;
        public String genereEvento;
    }

    public class CompensiWrapper {
        public List<CompensoDetail> compensi = new List<CompensoDetail>();
        public DirittiConnessiDetail dirittiConnessi;
    }

    public class FeItem {
        public String itemCode;
        public Decimal amount;
    }

    public class FeCostSection {
        public List<FeItem> vociIncasso = new List<FeItem>();
        public FeItem dap;
        public FeItem iva;
        public Decimal totalAmount;
    }

    public class FeLineItemDetail {
        public String lineItemId;
        public FeCostSection dda;
        public FeCostSection dc;
    }

    public class FeQuoteDetail {
        public List<FeLineItemDetail> lineItems = new List<FeLineItemDetail>();
    }


    public static void process(RCASalesTransaction contextResult) {
        validateContextResult(contextResult);
        Map<String, List<EventRuleResult>> rulesByLineItem = evaluateEventRules(contextResult.items);
        calculateDdaCompensi(contextResult.items, rulesByLineItem);
        calculateDc(contextResult.items, rulesByLineItem);
        buildFrontendLineDetails(contextResult.items);
        applyDap(contextResult.items);
        buildLineItemPaymentItems(contextResult.items);
        buildQuoteFrontendDetail(contextResult);
        applyFinalTotals(contextResult.items);
    }

    @TestVisible
    private static void validateContextResult(RCASalesTransaction contextResult) {
        if (contextResult == null || contextResult.items == null || contextResult.items.isEmpty()) {
            throw new TtppPricingException('No SalesTransactionItem found.');
        }
    }

    /**
     * Invoca la Decision Table UNA SOLA VOLTA in bulk per tutte le righe.
     * Salesforce supporta decisionTableAction + setInvocations(List<Map<String,Object>>).
     */
    @TestVisible
    private static Map<String, List<EventRuleResult>> evaluateEventRules(
        List<RCASalesTransaction.ItemNode> items
    ) {
        Map<String, List<EventRuleResult>> resultByLineItem = new Map<String, List<EventRuleResult>>();
        List<Map<String, Object>> invocations = new List<Map<String, Object>>();
        List<RCASalesTransaction.ItemNode> invokedItems = new List<RCASalesTransaction.ItemNode>();

        for (RCASalesTransaction.ItemNode item : items) {
            validateEventAttributes(item);
            invocations.add(buildDecisionTableInput(item));
            invokedItems.add(item);
        }

        Invocable.Action action = Invocable.Action.createCustomAction(
            'decisionTableAction',
            DECISION_TABLE_API_NAME
        );
        action.setInvocations(invocations);

        List<Invocable.Action.Result> actionResults = action.invoke();
        validateDecisionTableResultCount(invokedItems, actionResults);

        for (Integer i = 0; i < actionResults.size(); i++) {
            RCASalesTransaction.ItemNode item = invokedItems[i];
            Invocable.Action.Result actionResult = actionResults[i];
            validateDecisionTableActionResult(item, actionResult);
            resultByLineItem.put(
                item.lineItemId,
                parseDecisionTableOutput(actionResult.getOutputParameters())
            );
        }

        return resultByLineItem;
    }

    @TestVisible
    private static void calculateDdaCompensi(
        List<RCASalesTransaction.ItemNode> items,
        Map<String, List<EventRuleResult>> rulesByLineItem
    ) {
        for (RCASalesTransaction.ItemNode item : items) {
            List<EventRuleResult> rules = rulesByLineItem.get(item.lineItemId);
            validateRules(item, rules);
            item.pricingDetail = buildDdaCompensi(item, rules);
        }
    }

    @TestVisible
    private static void calculateDc(
        List<RCASalesTransaction.ItemNode> items,
        Map<String, List<EventRuleResult>> rulesByLineItem
    ) {
        for (RCASalesTransaction.ItemNode item : items) {
            applyDc(item, rulesByLineItem.get(item.lineItemId));
        }
    }

    @TestVisible
    private static void buildFrontendLineDetails(List<RCASalesTransaction.ItemNode> items) {
        for (RCASalesTransaction.ItemNode item : items) {
            item.frontendDetail = buildFrontendLineDetail(item, (CompensiWrapper) item.pricingDetail);
        }
    }

    @TestVisible
    private static void applyDap(List<RCASalesTransaction.ItemNode> items) {
        for (RCASalesTransaction.ItemNode item : items) {
            applyDapToFrontendDetail(item);
        }
    }

    @TestVisible
    private static void buildLineItemPaymentItems(List<RCASalesTransaction.ItemNode> items) {
        for (RCASalesTransaction.ItemNode item : items) {
            PricingPaymentItem.Wrapper wrapper = new PricingPaymentItem.Wrapper();

            // DDA: un payment item atomico per ogni genere/voce incasso risultante dal pricing.
            for (CompensoDetail compenso : ((CompensiWrapper) item.pricingDetail).compensi) {
                for (VoceIncassoDetail voce : compenso.vociIncasso) {
                    PricingPaymentItem paymentItem = createPaymentItem(
                        voce.voceIncasso,
                        voce.importoFinale,
                        PAYMENT_TYPE_DDA
                    );
                    paymentItem.eventGenre = compenso.genereEvento;
                    paymentItem.incidencePercentage = compenso.percentualeIncidenza;
                    wrapper.paymentItems.add(paymentItem);
                }
            }

            // DC: importo non splittato. Il genere viene associato alla riga DT che espone la voce DC.
            if (((CompensiWrapper) item.pricingDetail).dirittiConnessi != null) {
                PricingPaymentItem dcItem = createPaymentItem(
                    ((CompensiWrapper) item.pricingDetail).dirittiConnessi.voceIncasso,
                    ((CompensiWrapper) item.pricingDetail).dirittiConnessi.importoFinale,
                    PAYMENT_TYPE_DC
                );
                dcItem.eventGenre = ((CompensiWrapper) item.pricingDetail).dirittiConnessi.genereEvento;
                wrapper.paymentItems.add(dcItem);
            }

            // DAP: componenti fiscali autonome, non splittate per genere.
            if (item.totalDA != null && item.totalDA > 0) {
                wrapper.paymentItems.add(createPaymentItem(
                    ITEM_CODE_DAP_DDA, DAP_DDA_AMOUNT, PAYMENT_TYPE_DAP_DDA
                ));
            }
            if (item.dirittiConnessi != null && item.dirittiConnessi > 0) {
                wrapper.paymentItems.add(createPaymentItem(
                    ITEM_CODE_DAP_DC, DAP_DC_AMOUNT, PAYMENT_TYPE_DAP_DC
                ));
            }

            item.attributeToUpdate.put(FIELD_PAYMENT_ITEMS, JSON.serialize(wrapper));
        }
    }

    private static PricingPaymentItem createPaymentItem(String itemCode, Decimal amount, String type) {
        PricingPaymentItem item = new PricingPaymentItem();
        item.itemCode = itemCode;
        item.amount = RCAValueConverter.roundMoney(amount);
        item.type = type;
        return item;
    }

    @TestVisible
    private static void buildQuoteFrontendDetail(RCASalesTransaction contextResult) {
        Map<String, FeQuoteDetail> detailsByTransaction = aggregateFrontendDetails(contextResult.items);
        for (RCASalesTransaction.TransactionNode salesTransaction : contextResult.transactions) {
            FeQuoteDetail detail = detailsByTransaction.get(salesTransaction.transactionKey);
            if (detail != null) {
                salesTransaction.attributeToUpdate.put(FIELD_TTPP_FE_DETAIL_JSON, JSON.serialize(detail));
            }
        }
    }

    @TestVisible
    private static void applyFinalTotals(List<RCASalesTransaction.ItemNode> items) {
        for (RCASalesTransaction.ItemNode item : items) {
            applyFinalItemTotals(item);
        }
    }


    /* ========================= DECISION TABLE ========================= */

    @TestVisible
    private static Map<String, Object> buildDecisionTableInput(RCASalesTransaction.ItemNode item) {
        Datetime eventDate = item == null ? null : item.effectiveFrom == null ? item.derivedStartDateTime : RCAValueConverter.asDatetime(item.effectiveFrom) ;
        if (eventDate == null) {
            throw new TtppPricingException(
                'EffectiveFrom non valorizzato per line item ' +
                (item == null ? null : item.lineItemId) + '.'
            );
        }
        return new Map<String, Object>{
            DT_INPUT_MUSICA_DAL_VIVO => getBooleanAttribute(item, ATTR_MUSICA_DAL_VIVO),
            DT_INPUT_MUSICA_REGISTRATA => getBooleanAttribute(item, ATTR_MUSICA_REGISTRATA),
            DT_INPUT_BALLO => getBooleanAttribute(item, ATTR_BALLO),
            DT_INPUT_DATAINIZIOVALIDITA => eventDate,
            DT_INPUT_DATAFINEVALIDITA => eventDate
        };
    }

    @TestVisible
    private static void validateDecisionTableResultCount(
        List<RCASalesTransaction.ItemNode> items,
        List<Invocable.Action.Result> results
    ) {
        if (results == null || results.size() != items.size()) {
            throw new TtppPricingException(
                'Decision Table returned an unexpected result count. Expected ' +
                items.size() + ', received ' + (results == null ? 0 : results.size()) + '.'
            );
        }
    }

    @TestVisible
    private static void validateDecisionTableActionResult(
        RCASalesTransaction.ItemNode item,
        Invocable.Action.Result result
    ) {
        if (result == null || !result.isSuccess()) {
            String errors = result == null ? 'null result' : JSON.serialize(result.getErrors());
            throw new TtppPricingException(
                'Decision Table failed for line ' + item.lineItemId + ': ' + errors
            );
        }
    }

    /**
     * Parser volutamente tollerante: alcune configurazioni DT espongono la singola riga
     * direttamente negli output, altre espongono una collection di righe.
     * Dopo la creazione della DT, loggare getOutputParameters() in DEV e, se necessario,
     * allineare esclusivamente questo metodo/questi constant senza toccare l'orchestrazione.
     */
    @TestVisible
    private static List<EventRuleResult> parseDecisionTableOutput(Map<String, Object> outputParameters) {
        List<EventRuleResult> rules = new List<EventRuleResult>();
        if (outputParameters == null || outputParameters.isEmpty()) {
            return rules;
        }

        Object rawOutcomeList = outputParameters.get('outcomeList');
        if (rawOutcomeList != null) {
            List<Object> outcomes = (List<Object>) JSON.deserializeUntyped(JSON.serialize(rawOutcomeList));
            for (Object rawOutcome : outcomes) {
                Map<String, Object> row = (Map<String, Object>) rawOutcome;
                rules.add(toEventRule(row));
            }
            return rules;
        }

        Object rawSingleOutcome = outputParameters.get('singleOutcome');
        if (rawSingleOutcome != null) {
            Map<String, Object> row = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(rawSingleOutcome));
            rules.add(toEventRule(row));
        }
        return rules;
    }

    private static EventRuleResult toEventRule(Map<String, Object> row) {
        EventRuleResult rule = new EventRuleResult();
        rule.genereEvento = RCAValueConverter.asString(row.get(DT_OUTPUT_GENERE));
        rule.percentualeIncidenza = RCAValueConverter.asDecimal(row.get(DT_OUTPUT_PERCENTUALE));
        rule.voceIncassoDDA = RCAValueConverter.asString(row.get(DT_OUTPUT_VOCE_INCASSO_DDA));
        rule.voceIncassoDC = RCAValueConverter.asString(row.get(DT_OUTPUT_VOCE_INCASSO_DC));
        return rule;
    }

    /* ========================= BUSINESS METHODS ========================= */

    @TestVisible
    private static CompensiWrapper buildDdaCompensi(RCASalesTransaction.ItemNode item, List<EventRuleResult> rules) {
        CompensiWrapper wrapper = new CompensiWrapper();
        Decimal ddaToAllocate = RCAValueConverter.roundMoney(item.totalDA);
        Decimal allocated = 0;

        for (Integer i = 0; i < rules.size(); i++) {
            EventRuleResult rule = rules[i];
            CompensoDetail compenso = new CompensoDetail();
            compenso.genereEvento = rule.genereEvento;
            compenso.percentualeIncidenza = rule.percentualeIncidenza;

            // L'ultima quota assorbe l'eventuale centesimo residuo di arrotondamento.
            // Esempio: 110,57 al 50/50 -> 55,29 + 55,28, mai 55,29 + 55,29.
            Decimal amount = i == rules.size() - 1
                ? RCAValueConverter.roundMoney(ddaToAllocate - allocated)
                : calculatePercentageAmount(ddaToAllocate, rule.percentualeIncidenza);
            allocated = RCAValueConverter.roundMoney(allocated + amount);

            VoceIncassoDetail voce = new VoceIncassoDetail();
            voce.voceIncasso = rule.voceIncassoDDA;
            voce.tipoCosto = 'DDA';
            voce.importoFinale = amount;
            compenso.vociIncasso.add(voce);
            wrapper.compensi.add(compenso);
        }
        return wrapper;
    }

    @TestVisible
    private static void applyDc(
        RCASalesTransaction.ItemNode item,
        List<EventRuleResult> rules
    ) {
        if (item.dirittiConnessi == null || item.dirittiConnessi <= 0) {
            ((CompensiWrapper) item.pricingDetail).dirittiConnessi = null;
            return;
        }

        EventRuleResult dcRule = getUniqueDcRule(item, rules);
        if (dcRule == null || String.isBlank(dcRule.voceIncassoDC)) {
            throw new TtppPricingException(
                'SIAE_DirittiConnessi__c maggiore di 0 ma nessuna regola con voce incasso DC ' +
                'configurata in Decision Table per line item ' + item.lineItemId + '.'
            );
        }

        DirittiConnessiDetail detail = new DirittiConnessiDetail();
        detail.voceIncasso = dcRule.voceIncassoDC.trim();
        detail.importoFinale = RCAValueConverter.roundMoney(item.dirittiConnessi);
        detail.genereEvento = dcRule.genereEvento;
        ((CompensiWrapper) item.pricingDetail).dirittiConnessi = detail;
    }


    @TestVisible
    private static EventRuleResult getUniqueDcRule(RCASalesTransaction.ItemNode item, List<EventRuleResult> rules) {
        EventRuleResult dcRule;

        if (rules != null) {
            for (EventRuleResult rule : rules) {
                if (rule == null || String.isBlank(rule.voceIncassoDC)) {
                    continue;
                }

                if (dcRule != null) {
                    throw new TtppPricingException(
                        'Piu regole Decision Table espongono una voce incasso DC per il line item ' +
                        item.lineItemId + '. La voce DC deve essere valorizzata solo sulla regola ' +
                        'del genere a cui appartengono i diritti connessi.'
                    );
                }

                dcRule = rule;
            }
        }

        return dcRule;
    }

    @TestVisible
    private static FeLineItemDetail buildFrontendLineDetail(
        RCASalesTransaction.ItemNode item,
        CompensiWrapper compensiWrapper
    ) {
        FeLineItemDetail result = new FeLineItemDetail();
        result.lineItemId = item.lineItemId;
        result.dda = new FeCostSection();
        result.dc = new FeCostSection();

        for (CompensoDetail compenso : compensiWrapper.compensi) {
            for (VoceIncassoDetail voce : compenso.vociIncasso) {
                result.dda.vociIncasso.add(
                    createFeItem(voce.voceIncasso, voce.importoFinale)
                );
            }
        }

        if (compensiWrapper.dirittiConnessi != null) {
            result.dc.vociIncasso.add(
                createFeItem(
                    compensiWrapper.dirittiConnessi.voceIncasso,
                    compensiWrapper.dirittiConnessi.importoFinale
                )
            );
        }

        result.dda.iva = createFeItem(ITEM_CODE_IVA_DDA, item.totalTaxDA);
        result.dc.iva = createFeItem(ITEM_CODE_IVA_DC, item.totalTaxDC);
        return result;
    }

    @TestVisible
    private static void applyDapToFrontendDetail(RCASalesTransaction.ItemNode item) {
        Decimal dapDda = item.totalDA != null && item.totalDA > 0 ? DAP_DDA_AMOUNT : 0;
        Decimal dapDc = item.dirittiConnessi != null && item.dirittiConnessi > 0 ? DAP_DC_AMOUNT : 0;

        ((FeLineItemDetail) item.frontendDetail).dda.dap = createFeItem(ITEM_CODE_DAP_DDA, dapDda);
        ((FeLineItemDetail) item.frontendDetail).dc.dap = createFeItem(ITEM_CODE_DAP_DC, dapDc);

        ((FeLineItemDetail) item.frontendDetail).dda.totalAmount = RCAValueConverter.roundMoney(
            sumFeItems(((FeLineItemDetail) item.frontendDetail).dda.vociIncasso) + dapDda + safeDecimal(item.totalTaxDA)
        );
        ((FeLineItemDetail) item.frontendDetail).dc.totalAmount = RCAValueConverter.roundMoney(
            sumFeItems(((FeLineItemDetail) item.frontendDetail).dc.vociIncasso) + dapDc + safeDecimal(item.totalTaxDC)
        );
    }

    private static FeItem createFeItem(String itemCode, Decimal amount) {
        FeItem item = new FeItem();
        item.itemCode = itemCode;
        item.amount = RCAValueConverter.roundMoney(amount);
        return item;
    }

    private static Decimal sumFeItems(List<FeItem> items) {
        Decimal total = 0;
        if (items == null) return total;
        for (FeItem item : items) total += safeDecimal(item.amount);
        return RCAValueConverter.roundMoney(total);
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    @TestVisible
    private static void applyFinalItemTotals(RCASalesTransaction.ItemNode item) {
        Decimal dapDda = item.totalDA != null && item.totalDA > 0 ? DAP_DDA_AMOUNT : 0;
        Decimal dapDc = item.dirittiConnessi != null && item.dirittiConnessi > 0 ? DAP_DC_AMOUNT : 0;

        Decimal totalDaWithDap = RCAValueConverter.roundMoney(safeDecimal(item.totalDA) + dapDda);
        Decimal totalDcWithDap = RCAValueConverter.roundMoney(safeDecimal(item.dirittiConnessi) + dapDc);
        Decimal lineTotal = RCAValueConverter.roundMoney(totalDaWithDap + totalDcWithDap);

        item.attributeToUpdate.put(FIELD_TOTAL_DA, totalDaWithDap);
        item.attributeToUpdate.put(FIELD_DIRITTI_CONNESSI, totalDcWithDap);
        item.attributeToUpdate.put(FIELD_NET_TOTAL_PRICE, lineTotal);
        item.attributeToUpdate.put(FIELD_NET_UNIT_PRICE, lineTotal);
        item.attributeToUpdate.put(FIELD_TOTAL_LINE_AMOUNT, lineTotal);
        item.attributeToUpdate.put(FIELD_UNIT_PRICE, lineTotal);
    }

    @TestVisible
    private static Map<String, FeQuoteDetail> aggregateFrontendDetails(List<RCASalesTransaction.ItemNode> items) {
        Map<String, FeQuoteDetail> result = new Map<String, FeQuoteDetail>();
        for (RCASalesTransaction.ItemNode item : items) {
            if (String.isBlank(item.transactionKey) || ((FeLineItemDetail) item.frontendDetail) == null) continue;
            if (!result.containsKey(item.transactionKey)) {
                result.put(item.transactionKey, new FeQuoteDetail());
            }
            result.get(item.transactionKey).lineItems.add(((FeLineItemDetail) item.frontendDetail));
        }
        return result;
    }

    private static Decimal calculatePercentageAmount(Decimal total, Decimal percentage) {
        if (total == null || percentage == null) return 0;
        return RCAValueConverter.roundMoney(total * percentage / 100);
    }

    /* ========================= VALIDATION ========================= */

    @TestVisible
    private static void validateEventAttributes(RCASalesTransaction.ItemNode item) {
        List<String> missing = new List<String>();
        if (!item.attributeValueByCode.containsKey(ATTR_MUSICA_DAL_VIVO)) missing.add(ATTR_MUSICA_DAL_VIVO);
        if (!item.attributeValueByCode.containsKey(ATTR_MUSICA_REGISTRATA)) missing.add(ATTR_MUSICA_REGISTRATA);
        if (!item.attributeValueByCode.containsKey(ATTR_BALLO)) missing.add(ATTR_BALLO);
        //if (item.derivedStartDateTime == null) missing.add('DerivedStartDateTime__std');
        if (!missing.isEmpty()) {
            throw new TtppPricingException(
                'Attributi TTPP mancanti per line item ' + item.lineItemId + ': ' + String.join(missing, ', ')
            );
        }
    }

    @TestVisible
    private static void validateRules(RCASalesTransaction.ItemNode item, List<EventRuleResult> rules) {
        if (rules == null || rules.isEmpty()) {
            throw new TtppPricingException(
                'Nessuna regola Decision Table trovata per line item ' + item.lineItemId + '.'
            );
        }

        Decimal totalPercentage = 0;
        for (EventRuleResult rule : rules) {
            if (String.isBlank(rule.genereEvento) ||
                String.isBlank(rule.voceIncassoDDA) ||
                rule.percentualeIncidenza == null) {
                throw new TtppPricingException(
                    'Regola Decision Table incompleta per line item ' + item.lineItemId + '.'
                );
            }
            totalPercentage += rule.percentualeIncidenza;
        }

        if (totalPercentage != 100) {
            throw new TtppPricingException(
                'Le percentuali della Decision Table per line item ' + item.lineItemId +
                ' sommano ' + totalPercentage + ' invece di 100.'
            );
        }
    }

    /* ========================= GENERIC HELPERS ========================= */

    @TestVisible
    private static Boolean getBooleanAttribute(RCASalesTransaction.ItemNode item, String code) {
        return RCAValueConverter.asBoolean(item == null ? null : item.attributeValueByCode.get(code));
    }


    public class TtppPricingException extends Exception { }
}