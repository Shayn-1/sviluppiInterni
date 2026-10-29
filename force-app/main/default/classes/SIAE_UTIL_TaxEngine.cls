/**
 * @description SIAE Tax Engine — RLM Tax Provider (commercetax.TaxEngineAdapter).
 *              La tassazione (imposte DDA, imposte DC, bollo DDA/DC) è delegata a SAP (servizio Fatt14)
 *              tramite callout sincrono orchestrato da Mulesoft (SIAE_REST_CalculateTax).
 *              RLM persiste i dettagli tasse in QuoteItemTaxItem (Name='DA'/'DC'/'BOLLO_DDA'/'BOLLO_DC').
 *              Il trigger SIAE_TR_QuoteLineItem_U_ManageTaxes legge QuoteItemTaxItem quando RLM aggiorna
 *              TotalTaxAmount e persiste i campi custom SIAE (stessa transazione, nessuna cache necessaria).
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
global class SIAE_UTIL_TaxEngine implements commercetax.TaxEngineAdapter {

    @TestVisible
    private enum ContextType { QUOTE, ORDER }

    private static final Set<String> DDA_TYPES = new Set<String>{ 'DDA', 'SI_DDA' };
    private static final Set<String> DC_TYPES  = new Set<String>{ 'DC', 'SI_DC' };

    global commercetax.TaxEngineResponse processRequest(commercetax.TaxEngineContext taxEngineContext) {
        if (taxEngineContext == null) {
            return buildError('400', 'taxEngineContext is mandatory');
        }
        commercetax.RequestType requestType = taxEngineContext.getRequestType();
        commercetax.CalculateTaxRequest request = (commercetax.CalculateTaxRequest) taxEngineContext.getRequest();

        if (request == null || request.documentCode == null) { return buildError('400', 'CalculateTaxRequest and documentCode are mandatory'); }

        try {
            if (requestType == commercetax.RequestType.CalculateTax) { return handleCalculateTax(request); }
            return null;
        }
        catch (SIAETaxEngineException e) { return buildError(e.errorCode, e.getMessage()); }
        catch (Exception e) { System.debug(LoggingLevel.ERROR, 'SIAE_UTIL_TaxEngine unhandled exception: ' + e.getMessage() + '\n' + e.getStackTraceString()); return buildError('500', 'Unexpected error: ' + e.getMessage()); }
    }

    @TestVisible
    private commercetax.TaxEngineResponse handleCalculateTax(commercetax.CalculateTaxRequest request) {
        ContextType ctx = detectContext(request.referenceEntityId);

        TaxCalculationInput input = toTaxCalculationInput(request, ctx);
        TaxCalculationOutput output = calculateTaxCore(input);

        return buildCalculateTaxResponse(request, output.calcResultByLineId);
    }

    @TestVisible
    private TaxCalculationInput toTaxCalculationInput(
        commercetax.CalculateTaxRequest request,
        ContextType ctx
    ) {
        TaxCalculationInput input = new TaxCalculationInput();

        if (request == null) { return input; }

        input.referenceEntityId = request.referenceEntityId;
        input.contextType = ctx;
        input.documentCode = request.documentCode;
        input.referenceDocumentCode = request.referenceDocumentCode;
        input.taxType = request.taxtype == null ? null : String.valueOf(request.taxtype);
        input.currencyIsoCode = request.currencyIsoCode;
        input.transactionDate = request.transactionDate;
        input.isCommit = request.isCommit;

        if (request.lineItems != null) {
            for (commercetax.TaxLineItemRequest lineItem : request.lineItems) {
                if (lineItem == null) {  continue; }

                TaxCalculationLineInput line = new TaxCalculationLineInput();
                line.lineNumber = lineItem.lineNumber;
                line.amount = lineItem.amount;
                line.taxCode = lineItem.taxCode;
                line.productCode = lineItem.productCode;
                line.quantity = lineItem.quantity;
                input.lines.add(line);
            }
        }

        return input;
    }

    /**
     * Core di calcolo: costruisce la request SAP, esegue il callout e popola l'output.
     * Supporta sia contesto Quote (referenceEntityId = Quote ID, lineNumber = QLI ID)
     * sia contesto Order (referenceEntityId = Order ID, lineNumber = OrderItem ID).
     */
    @TestVisible
    private TaxCalculationOutput calculateTaxCore(TaxCalculationInput input) {
        TaxCalculationOutput output = new TaxCalculationOutput();

        if (input == null || input.lines == null || input.lines.isEmpty()) {
            return output;
        }

        ContextType ctx = input.contextType != null
            ? input.contextType
            : detectContext(input.referenceEntityId);

        Set<String> lineItemIds = new Set<String>();
        for (TaxCalculationLineInput lineItem : input.lines) {
            if (lineItem != null && String.isNotBlank(lineItem.lineNumber)) {
                lineItemIds.add(lineItem.lineNumber.left(15));
            }
        }

        if (lineItemIds.isEmpty()) {
            return output;
        }

        Map<String, QuoteLineData> dataByLineId = (ctx == ContextType.QUOTE)
            ? queryQuoteLineData(lineItemIds)
            : queryOrderLineData(lineItemIds);
        QuoteHeader header = (ctx == ContextType.QUOTE)
            ? resolveQuoteHeader(input.referenceEntityId)
            : resolveOrderHeader(input.referenceEntityId);

        SIAE_REST_CalculateTax.Request sapRequest = buildSapRequest(header, input.lines, dataByLineId);
        SIAE_REST_CalculateTax.CalculateTaxResult sapResult = SIAE_REST_CalculateTax.calculate(sapRequest);

        if (sapResult == null || !sapResult.success) {
            String errMsg = (sapResult != null && String.isNotBlank(sapResult.errorMessage))
                ? sapResult.errorMessage
                : 'SAP callout failed (no response)';
            throw new SIAETaxEngineException('503', errMsg);
        }

        for (TaxCalculationLineInput lineItem : input.lines) {
            if (lineItem == null || String.isBlank(lineItem.lineNumber)) { continue; }

            String lineId15 = lineItem.lineNumber.left(15);
            TaxCalcResult res = new TaxCalcResult();

            SIAE_REST_CalculateTax.QuoteLineItemResponse sapLine =
                sapResult.taxByLineId != null
                    ? sapResult.taxByLineId.get(lineId15)
                    : null;

            if (sapLine != null) {
                res.sapDataReceived  = true;
                res.totalTaxDA       = toDecimal(sapLine.importoImposteDda);
                res.totalTaxDC       = toDecimal(sapLine.importoImposteDc);
                res.totalTaxBolloDDA = toDecimal(sapLine.importoBolloDda);
                res.totalTaxBolloDC  = toDecimal(sapLine.importoBolloDc);
                res.totalTax = res.totalTaxDA + res.totalTaxDC + res.totalTaxBolloDDA + res.totalTaxBolloDC;
            }

            output.calcResultByLineId.put(lineId15, res);
            output.grandTotalAmount += lineItem.amount != null ? lineItem.amount : 0;
            output.grandTotalTax += res.totalTax;
        }

        return output;
    }

    @TestVisible
    private SIAE_REST_CalculateTax.Request buildSapRequest(
        QuoteHeader header,
        List<TaxCalculationLineInput> lines,
        Map<String, QuoteLineData> dataByLineId
    ) {
        SIAE_REST_CalculateTax.Request req = new SIAE_REST_CalculateTax.Request();
        req.idSap                   = header != null ? header.idSap : null;
        req.seprag                  = header != null ? header.seprag : null;
        req.idCarrello              = header != null ? header.quoteId : null;
        req.flagNoBollo             = false;
        req.flagExtraTerritorialita = false;

        if (lines == null) { return req; }

        for (TaxCalculationLineInput line : lines) {
            if (line == null || String.isBlank(line.lineNumber)) { continue; }

            String lineId15 = line.lineNumber.left(15);
            QuoteLineData data = dataByLineId != null ? dataByLineId.get(lineId15) : null;
            if (data == null) { continue; }

            SIAE_REST_CalculateTax.QuoteLineItemRequest qli =
                new SIAE_REST_CalculateTax.QuoteLineItemRequest();
            qli.id        = data.lineId;
            qli.totaleDda = String.valueOf(data.totaleDda != null ? data.totaleDda : 0);
            qli.totaleDc  = String.valueOf(data.totaleDc  != null ? data.totaleDc  : 0);

            for (PaymentItemWrapper item : parsePaymentItems(data.paymentItemsJson)) {
                if (item == null || String.isBlank(item.type)) { continue; }
                SIAE_REST_CalculateTax.VoceCosto voce = toVoceCosto(item);
                if (DDA_TYPES.contains(item.type)) {
                    qli.vociCostoDda.add(voce);
                } else if (DC_TYPES.contains(item.type)) {
                    qli.vociCostoDc.add(voce);
                }
                // type 'QA' (quota associativa) escluso di default — vedi punto aperto documentazione.
            }

            req.quoteLineItem.add(qli);
        }

        return req;
    }

    private SIAE_REST_CalculateTax.VoceCosto toVoceCosto(PaymentItemWrapper item) {
        SIAE_REST_CalculateTax.VoceCosto voce = new SIAE_REST_CalculateTax.VoceCosto();
        voce.voceIncasso = item.itemCode;
        voce.quantita    = '1';
        voce.importo     = item.amount != null ? String.valueOf(item.amount) : '0';
        return voce;
    }

    @TestVisible
    private Map<String, QuoteLineData> queryQuoteLineData(Set<String> lineItemIds) {
        Map<String, QuoteLineData> result = new Map<String, QuoteLineData>();
        if (lineItemIds == null || lineItemIds.isEmpty()) { return result; }

        for (QuoteLineItem qli : [
            SELECT Id, SIAE_PaymentItems__c, SIAE_TotalDA__c, SIAE_DirittiConnessi__c
            FROM QuoteLineItem
            WHERE Id IN :lineItemIds
        ]) {
            QuoteLineData data = new QuoteLineData();
            data.lineId           = String.valueOf(qli.Id);
            data.paymentItemsJson = qli.SIAE_PaymentItems__c;
            data.totaleDda        = qli.SIAE_TotalDA__c;
            data.totaleDc         = qli.SIAE_DirittiConnessi__c;
            result.put(String.valueOf(qli.Id).left(15), data);
        }
        return result;
    }

    @TestVisible
    private ContextType detectContext(String referenceEntityId) {
        if (String.isBlank(referenceEntityId)) {
            throw new SIAETaxEngineException('400', 'referenceEntityId is blank.');
        }
        try {
            String objectName = ((Id) referenceEntityId).getSObjectType().getDescribe().getName();
            if (objectName == 'Quote') return ContextType.QUOTE;
            if (objectName == 'Order') return ContextType.ORDER;
            throw new SIAETaxEngineException('400', 'Unsupported referenceEntityId object type: ' + objectName);
        } catch (SIAETaxEngineException e) {
            throw e;
        } catch (Exception e) {
            throw new SIAETaxEngineException('400', 'Invalid referenceEntityId: ' + referenceEntityId);
        }
    }

    @TestVisible
    private QuoteHeader resolveQuoteHeader(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new SIAETaxEngineException('400', 'referenceEntityId (Quote ID) is blank.');
        }
        List<Quote> quotes = [
            SELECT Id, SIAE_Seprag__c, QuoteAccountId, QuoteAccount.SIAE_IDSap__c
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            throw new SIAETaxEngineException('404', 'Quote not found for referenceEntityId: ' + quoteId);
        }
        QuoteHeader header = new QuoteHeader();
        header.quoteId = quotes[0].Id;
        header.seprag  = quotes[0].SIAE_Seprag__c;
        header.idSap   = (quotes[0].QuoteAccount != null) ? quotes[0].QuoteAccount.SIAE_IDSap__c : null;
        if (String.isBlank(header.idSap)) {
            System.debug(LoggingLevel.WARN, 'SIAE_UTIL_TaxEngine: Quote ' + quoteId + ' senza idSap risolvibile (QuoteAccount.SIAE_IDSap__c).');
        }
        return header;
    }

    @TestVisible
    private QuoteHeader resolveOrderHeader(String orderId) {
        if (String.isBlank(orderId)) {
            throw new SIAETaxEngineException('400', 'referenceEntityId (Order ID) is blank.');
        }
        List<Order> orders = [
            SELECT Id, SIAE_Seprag__c, AccountId, Account.SIAE_IDSap__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            throw new SIAETaxEngineException('404', 'Order not found for referenceEntityId: ' + orderId);
        }
        QuoteHeader header = new QuoteHeader();
        header.quoteId = orders[0].Id;
        header.seprag  = orders[0].SIAE_Seprag__c;
        header.idSap   = (orders[0].Account != null) ? orders[0].Account.SIAE_IDSap__c : null;
        if (String.isBlank(header.idSap)) {
            System.debug(LoggingLevel.WARN, 'SIAE_UTIL_TaxEngine: Order ' + orderId + ' senza idSap risolvibile (Account.SIAE_IDSap__c).');
        }
        return header;
    }

    @TestVisible
    private Map<String, QuoteLineData> queryOrderLineData(Set<String> lineItemIds) {
        Map<String, QuoteLineData> result = new Map<String, QuoteLineData>();
        if (lineItemIds == null || lineItemIds.isEmpty()) { return result; }

        for (OrderItem oi : [
            SELECT Id, SIAE_PaymentItems__c, SIAE_TotalDA__c, SIAE_DirittiConnessi__c
            FROM OrderItem
            WHERE Id IN :lineItemIds
        ]) {
            QuoteLineData data = new QuoteLineData();
            data.lineId           = String.valueOf(oi.Id);
            data.paymentItemsJson = oi.SIAE_PaymentItems__c;
            data.totaleDda        = oi.SIAE_TotalDA__c;
            data.totaleDc         = oi.SIAE_DirittiConnessi__c;
            result.put(String.valueOf(oi.Id).left(15), data);
        }
        return result;
    }

    @TestVisible
    private List<PaymentItemWrapper> parsePaymentItems(String jsonStr) {
        List<PaymentItemWrapper> result = new List<PaymentItemWrapper>();
        if (String.isBlank(jsonStr)) return result;
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            List<Object> rawItems = (List<Object>) root.get('paymentItems');
            if (rawItems == null) return result;
            for (Object rawItem : rawItems) {
                Map<String, Object> itemMap = (Map<String, Object>) rawItem;
                String itemCode = itemMap.get('itemCode') != null
                    ? String.valueOf(itemMap.get('itemCode'))
                    : null;
                Object rawAmount = itemMap.get('amount');
                Decimal amount = toPaymentItemDecimal(rawAmount);

                if (String.isBlank(itemCode) || amount == null) continue;

                PaymentItemWrapper wrapper = new PaymentItemWrapper();
                wrapper.itemCode = itemCode;
                wrapper.amount = amount;
                wrapper.type = itemMap.get('type') != null
                    ? String.valueOf(itemMap.get('type'))
                    : '';

                result.add(wrapper);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SIAE_UTIL_TaxEngine: parsePaymentItems failed — ' + e.getMessage() + ' | JSON: ' + jsonStr);
        }
        return result;
    }


    private static Decimal toPaymentItemDecimal(Object value) {
        if (value == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(value).trim().replace(',', '.'));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal toDecimal(String value) {
        if (String.isBlank(value)) return 0;
        try {
            return Decimal.valueOf(value.trim().replace(',', '.'));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SIAE_UTIL_TaxEngine: importo SAP non parsabile: ' + value);
            return 0;
        }
    }

    @TestVisible
    private commercetax.CalculateTaxResponse buildCalculateTaxResponse(
        commercetax.CalculateTaxRequest request,
        Map<String, TaxCalcResult> calcResultByLineId
    ) {
        commercetax.CalculateTaxResponse response = new commercetax.CalculateTaxResponse();

        if (request == null) return response;

        response.setStatus(request.isCommit == true
            ? commercetax.TaxTransactionStatus.Committed
            : commercetax.TaxTransactionStatus.Uncommitted);
        response.setDocumentCode(request.documentCode);
        response.setReferenceDocumentCode(request.referenceDocumentCode);
        response.setReferenceEntityId(request.referenceEntityId);
        response.setTaxType(request.taxtype);
        response.setTaxTransactionType(request.taxTransactionType != null
            ? request.taxTransactionType
            : commercetax.TaxTransactionType.Debit);
        response.setCurrencyIsoCode(String.isNotBlank(request.currencyIsoCode) ? request.currencyIsoCode : 'EUR');
        response.setEffectiveDate(System.now());
        response.setTransactionDate(request.transactionDate != null ? request.transactionDate : System.now());
        response.setDescription('SIAE Tax Engine');
        response.setStatusDescription('Tax calculation completed');
        response.setAddresses(buildDefaultAddresses());

        TaxResponseBuildResult lineBuildResult =
            buildLineItemResponsesFromManagedRequest(request, calcResultByLineId);

        response.setLineItems(lineBuildResult.lineResponses);
        response.setAmountDetails(
            buildAmountDetails(
                lineBuildResult.grandTotalAmount,
                lineBuildResult.grandTotalTax
            )
        );

        return response;
    }

    @TestVisible
    private TaxResponseBuildResult buildLineItemResponsesFromManagedRequest(
        commercetax.CalculateTaxRequest request,
        Map<String, TaxCalcResult> calcResultByLineId
    ) {
        TaxResponseBuildResult result = new TaxResponseBuildResult();

        if (request == null || request.lineItems == null) { return result; }

        List<TaxLineResponseInput> lines = new List<TaxLineResponseInput>();

        for (commercetax.TaxLineItemRequest lineItem : request.lineItems) { lines.add(toTaxLineResponseInput(lineItem)); }

        return buildLineItemResponsesFromInput(lines, calcResultByLineId);
    }

    @TestVisible
    private TaxLineResponseInput toTaxLineResponseInput(
        commercetax.TaxLineItemRequest lineItem
    ) {
        TaxLineResponseInput input = new TaxLineResponseInput();

        if (lineItem == null) { return input; }

        input.lineNumber = lineItem.lineNumber;
        input.taxCode = lineItem.taxCode;
        input.productCode = lineItem.productCode;
        input.quantity = lineItem.quantity;
        input.amount = lineItem.amount;

        return input;
    }

    @TestVisible
    private TaxResponseBuildResult buildLineItemResponsesFromInput(
        List<TaxLineResponseInput> lineItems,
        Map<String, TaxCalcResult> calcResultByLineId
    ) {
        TaxResponseBuildResult result = new TaxResponseBuildResult();

        if (lineItems == null || lineItems.isEmpty()) {
            return result;
        }

        for (TaxLineResponseInput lineItem : lineItems) {
            String lineId15 = lineItem != null && lineItem.lineNumber != null
                ? lineItem.lineNumber.left(15)
                : null;

            TaxCalcResult calcResult =
                lineId15 != null &&
                calcResultByLineId != null &&
                calcResultByLineId.containsKey(lineId15)
                    ? calcResultByLineId.get(lineId15)
                    : new TaxCalcResult();

            result.lineResponses.add(buildLineItemResponseFromInput(lineItem, calcResult));
            result.grandTotalTax += calcResult.totalTax;
            result.grandTotalAmount += lineItem != null && lineItem.amount != null
                ? lineItem.amount
                : 0;
        }

        return result;
    }

    @TestVisible
    private commercetax.LineItemResponse buildLineItemResponseFromInput(
        TaxLineResponseInput lineItem,
        TaxCalcResult calcResult
    ) {
        commercetax.LineItemResponse lineResponse = new commercetax.LineItemResponse();

        if (lineItem == null) {
            return lineResponse;
        }

        if (calcResult == null) {
            calcResult = new TaxCalcResult();
        }

        lineResponse.setLineNumber(lineItem.lineNumber);
        lineResponse.setTaxCode(lineItem.taxCode);
        lineResponse.setProductCode(lineItem.productCode);
        lineResponse.setIsTaxable(true);
        lineResponse.setEffectiveDate(System.now());
        lineResponse.setAddresses(buildDefaultAddresses());

        List<commercetax.TaxDetailsResponse> taxDetails =
            new List<commercetax.TaxDetailsResponse>();

        if (calcResult.totalTaxDA > 0) {
            taxDetails.add(buildAggregateTaxDetailsResponse('DA', calcResult.totalTaxDA));
        }
        if (calcResult.totalTaxDC > 0) {
            taxDetails.add(buildAggregateTaxDetailsResponse('DC', calcResult.totalTaxDC));
        }
        if (calcResult.totalTaxBolloDDA > 0) {
            taxDetails.add(buildAggregateTaxDetailsResponse('BOLLO_DDA', calcResult.totalTaxBolloDDA));
        }
        if (calcResult.totalTaxBolloDC > 0) {
            taxDetails.add(buildAggregateTaxDetailsResponse('BOLLO_DC', calcResult.totalTaxBolloDC));
        }

        lineResponse.setTaxes(taxDetails);

        Decimal lineAmount = lineItem.amount != null ? lineItem.amount : 0;
        lineResponse.setAmountDetails(buildAmountDetails(lineAmount, calcResult.totalTax));

        return lineResponse;
    }

    @TestVisible
    private commercetax.TaxDetailsResponse buildAggregateTaxDetailsResponse(String type, Decimal tax) {
        commercetax.TaxDetailsResponse taxDetail = new commercetax.TaxDetailsResponse();
        taxDetail.setRate(0);
        taxDetail.setTaxableAmount(0);
        taxDetail.setTax(tax != null ? tax.doubleValue() : 0);
        taxDetail.setExemptAmount(0);

        commercetax.ImpositionResponse imposition = new commercetax.ImpositionResponse();
        imposition.setType(type);
        imposition.setSubType('SIAE');
        taxDetail.setImposition(imposition);

        commercetax.JurisdictionResponse jurisdiction = new commercetax.JurisdictionResponse();
        jurisdiction.setCountry('Italy');
        jurisdiction.setRegion('IT');
        jurisdiction.setName('Italy');
        taxDetail.setJurisdiction(jurisdiction);

        return taxDetail;
    }

    @TestVisible
    private commercetax.AmountDetailsResponse buildAmountDetails(Decimal totalAmount, Decimal totalTax) {
        commercetax.AmountDetailsResponse details = new commercetax.AmountDetailsResponse();
        details.setTotalAmount(totalAmount.doubleValue());
        details.setTaxAmount(totalTax.doubleValue());
        details.setTotalAmountWithTax((totalAmount + totalTax).doubleValue());
        details.setExemptAmount(0);
        return details;
    }

    @TestVisible
    private commercetax.AddressesResponse buildDefaultAddresses() {
        commercetax.AddressResponse addr = new commercetax.AddressResponse();
        addr.setLocationCode('IT');
        commercetax.AddressesResponse addresses = new commercetax.AddressesResponse();
        addresses.setShipFrom(addr);
        addresses.setShipTo(addr);
        addresses.setSoldTo(addr);
        return addresses;
    }

    @TestVisible
    private commercetax.ErrorResponse buildError(String code, String message) {
        return new commercetax.ErrorResponse(commercetax.resultcode.TaxEngineError, code, message);
    }

    @TestVisible
    private class TaxLineResponseInput {
        @TestVisible String lineNumber;
        @TestVisible String taxCode;
        @TestVisible String productCode;
        @TestVisible Decimal quantity;
        @TestVisible Decimal amount;
    }

    @TestVisible
    private class TaxResponseBuildResult {
        @TestVisible List<commercetax.LineItemResponse> lineResponses =
            new List<commercetax.LineItemResponse>();
        @TestVisible Decimal grandTotalTax = 0;
        @TestVisible Decimal grandTotalAmount = 0;
    }

    @TestVisible
    private class TaxCalculationInput {
        @TestVisible String referenceEntityId;
        @TestVisible ContextType contextType;
        @TestVisible String documentCode;
        @TestVisible String referenceDocumentCode;
        @TestVisible String taxType;
        @TestVisible String currencyIsoCode;
        @TestVisible Datetime transactionDate;
        @TestVisible Boolean isCommit;
        @TestVisible List<TaxCalculationLineInput> lines = new List<TaxCalculationLineInput>();
    }

    @TestVisible
    private class TaxCalculationLineInput {
        @TestVisible String lineNumber;
        @TestVisible Decimal amount;
        @TestVisible String taxCode;
        @TestVisible String productCode;
        @TestVisible Decimal quantity;
    }

    @TestVisible
    private class TaxCalculationOutput {
        @TestVisible Map<String, TaxCalcResult> calcResultByLineId = new Map<String, TaxCalcResult>();
        @TestVisible Decimal grandTotalTax = 0;
        @TestVisible Decimal grandTotalAmount = 0;
    }

    @TestVisible
    private class QuoteHeader {
        @TestVisible String quoteId;
        @TestVisible String idSap;
        @TestVisible String seprag;
    }

    @TestVisible
    private class QuoteLineData {
        @TestVisible String lineId;
        @TestVisible String paymentItemsJson;
        @TestVisible Decimal totaleDda;
        @TestVisible Decimal totaleDc;
    }

    @TestVisible
    private class PaymentItemWrapper {
        @TestVisible String  itemCode;
        @TestVisible Decimal amount;
        @TestVisible String  type;
    }

    @TestVisible
    public class TaxCalcResult {
        @TestVisible public Boolean sapDataReceived   = false;
        @TestVisible public Decimal totalTax          = 0;
        @TestVisible public Decimal totalTaxDA        = 0;
        @TestVisible public Decimal totalTaxDC        = 0;
        @TestVisible public Decimal totalTaxBolloDDA  = 0;
        @TestVisible public Decimal totalTaxBolloDC   = 0;
    }

    private class SIAETaxEngineException extends Exception {
        String errorCode;
        SIAETaxEngineException(String code, String msg) {
            this(msg);
            this.errorCode = code;
        }
    }

}