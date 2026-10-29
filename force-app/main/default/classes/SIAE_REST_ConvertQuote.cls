/**
 * @description       : REST endpoint to convert a Quote to an Order and store acceptance flags
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 07-03-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
@RestResource(urlMapping='/SIAE/convertQuote/*')
global with sharing class SIAE_REST_ConvertQuote {

    public class ConvertQuoteRequest {
        public String  quoteId;
        public Boolean generalCondition;
        public Boolean specialTerms;
        public Boolean dataTruthfulness;
        public Boolean consentGDPR;
        public String  acceptanceDate;
        public Boolean includeDC;
    }


    public class FlowException extends Exception {}

    public class PostResponse {
        public Boolean success;
        public String  orderId;
        public String  errorMessage;
        public String referenceId;
        public String sapClientCode;
        public Double netAmount;
        public Double totalAmount;
        public Double taxAmount;
        public Double stampAmount;
        public List<Discounts> discounts;
    }

    public class Discounts {
        public String type;
        public String  label;
        public Double  amount;
    }

    @TestVisible
    private static Id testOrderId;

    @TestVisible
    private static Boolean testForceBlankOrderId = false;

    @TestVisible
    private static Boolean testForceEmptyOrderQuery = false;

    @HttpPost
    global static void postConvertQuote() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        PostResponse restResponse = new PostResponse();

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            String jsonRequest = req != null && req.requestBody != null ? req.requestBody.toString() : null;

            restResponse = executeConvertQuote(jsonRequest);
            if(restResponse.success){
                restResponse.success = true;
                restResponse.orderId = restResponse.orderId;
                restResponse.referenceId = restResponse.referenceId;
                restResponse.errorMessage = '';
            }else{
                res.statusCode = 500;
                restResponse.success = false;
                restResponse.errorMessage = 'Internal error, please try again. If the error persist, contact a Salesforce Admin.';
                restResponse.orderId = null;
            }
            
        } catch (IllegalArgumentException e) {
            res.statusCode = 400;
            restResponse.success = false;
            restResponse.errorMessage = e.getMessage();
            restResponse.orderId = null;
        } catch (FlowException e) {
            res.statusCode = 500;
            restResponse.success = false;
            restResponse.errorMessage = e.getMessage();
            restResponse.orderId = null;
        }

        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(restResponse));
    }

    @TestVisible
    public static PostResponse executeConvertQuote(String jsonRequest) {
        PostResponse convResponse = new PostResponse();
        if (String.isBlank(jsonRequest)) {
            throw new IllegalArgumentException('Request body is mandatory.');
        }

        ConvertQuoteRequest input =
            (ConvertQuoteRequest) JSON.deserialize(jsonRequest, ConvertQuoteRequest.class);

        if (input == null) {  throw new IllegalArgumentException('Request body is mandatory.'); }

        if (String.isBlank(input.quoteId)) {
            throw new IllegalArgumentException('quoteId is mandatory.');
        }

        List<Quote> listOfQuote = new List<Quote>([SELECT Id FROM Quote WHERE Id =: input.quoteId]);
        if(listOfQuote.isEmpty()){
            throw new IllegalArgumentException('The quoteId field does not exist or has been deleted; please try again with a valid quoteId.');
        }

        if (String.isBlank(input.acceptanceDate)) {
            throw new IllegalArgumentException('acceptanceDate is mandatory.');
        }

        validateBooleanFlag(input.generalCondition, 'generalCondition');
        validateBooleanFlag(input.specialTerms, 'specialTerms');
        validateBooleanFlag(input.dataTruthfulness, 'dataTruthfulness');
        validateBooleanFlag(input.consentGDPR, 'consentGDPR');

        Date acceptanceDateParsed = parseAcceptanceDate(input.acceptanceDate);

        String orderId = convertQuoteToOrder(input.quoteId);

        if(String.isBlank(orderId)){
            convResponse.orderId = '';
            convResponse.referenceId = '';
            convResponse.success = false;
            return convResponse;
        }

        Order ordToUpdate = new Order();
        ordToUpdate.Id = orderId;
        ordToUpdate.SIAE_GeneralCondition__c = true;
        ordToUpdate.SIAE_SpecialTerms__c = true;
        ordToUpdate.SIAE_DataTruthfulness__c = true;
        ordToUpdate.SIAE_ConsentGDPR__c = true;
        ordToUpdate.SIAE_AcceptanceDate__c = acceptanceDateParsed;
        ordToUpdate.SIAE_IncludeDC__c = input.includeDC;

        update ordToUpdate;
        List<Order> listOfOrder = new List<Order>([SELECT Id, SIAE_ReferenceId__c, Account.SIAE_IDSap__c, SIAE_IncludeDC__c,  SIAE_TotalDA__c, SIAE_TotalDC__c, SIAE_TotalTaxDA__c, SIAE_TotalTaxDC__c, SIAE_TotalBolloDA__c, SIAE_TotalBolloDC__c, SIAE_TotalDiscountCADA__c, SIAE_TotalDiscountCADC__c FROM Order WHERE Id =: orderId]);

        if (Test.isRunningTest() && testForceEmptyOrderQuery) {
            listOfOrder = new List<Order>();
        }

        if(listOfOrder.isEmpty()){
            convResponse.orderId = '';
            convResponse.referenceId = '';
            convResponse.success = false;
            return convResponse;
        }
        Order ord = listOfOrder[0];
        Boolean includeDc = ord.SIAE_IncludeDC__c;
        convResponse.netAmount = includeDc ? ord.SIAE_TotalDA__c + ord.SIAE_TotalDC__c : ord.SIAE_TotalDA__c;
        convResponse.totalAmount = includeDc ? ord.SIAE_TotalDA__c + ord.SIAE_TotalDC__c + ord.SIAE_TotalTaxDA__c + ord.SIAE_TotalTaxDC__c + ord.SIAE_TotalBolloDA__c + ord.SIAE_TotalBolloDC__c: ord.SIAE_TotalDA__c + ord.SIAE_TotalTaxDA__c + ord.SIAE_TotalBolloDA__c;
        convResponse.stampAmount = includeDc ? ord.SIAE_TotalBolloDA__c + ord.SIAE_TotalBolloDC__c : ord.SIAE_TotalBolloDA__c;
        //convResponse.taxAmount = includeDc ? (ord.SIAE_TotalTaxDA__c - ord.SIAE_TotalBolloDA__c) + (ord.SIAE_TotalTaxDC__c - ord.SIAE_TotalBolloDC__c) : ord.SIAE_TotalTaxDA__c - ord.SIAE_TotalBolloDA__c;
        convResponse.taxAmount = includeDc ? ord.SIAE_TotalTaxDA__c + ord.SIAE_TotalTaxDC__c : ord.SIAE_TotalTaxDA__c;
        convResponse.sapClientCode = ord.Account.SIAE_IDSap__c;
        Discounts discount = new Discounts();
        if((ord.SIAE_TotalDiscountCADA__c != null && ord.SIAE_TotalDiscountCADA__c > 0) || (ord.SIAE_TotalDiscountCADC__c != null && ord.SIAE_TotalDiscountCADC__c > 0)){
            discount.amount = includeDc ?  ord.SIAE_TotalDiscountCADA__c + ord.SIAE_TotalDiscountCADC__c : ord.SIAE_TotalDiscountCADA__c > 0 ? ord.SIAE_TotalDiscountCADA__c : null;
            discount.type = 'DISCOUNT';
            discount.label = 'Sconto di categoria';
            convResponse.discounts = new List<Discounts>{discount};
        }
       

        convResponse.orderId = orderId;
        convResponse.referenceId = listOfOrder[0].SIAE_ReferenceId__c;
        convResponse.success = true;
        return convResponse;
    }

    @TestVisible
    private static String convertQuoteToOrder(String quoteId) {
        if (Test.isRunningTest()) {
            if (testOrderId == null) {
                throw new FlowException(
                    'Internal error, please try again. If the error persists contact a salesforce admin.'
                );
            }

            if (testForceBlankOrderId) {
                return '';
            }

            return String.valueOf(testOrderId);
        }

        List<String> orderIds;
        Map<String, Object> inputFlow = new Map<String, Object>{ 'quoteId' => quoteId };

        try {
            Flow.Interview.SIAE_AL_CreateOrderFromQuote flowExecution =
                new Flow.Interview.SIAE_AL_CreateOrderFromQuote(inputFlow);

            flowExecution.start();

            orderIds = (List<String>) flowExecution.getVariableValue('orderIds');

            if (orderIds.isEmpty() && orderIds[0] == null) {
                throw new FlowException(
                    'Internal error, please try again. If the error persists contact a salesforce admin.'
                );
            }
        } 
        catch (FlowException e) {  throw e; } 
        catch (Exception e) { throw new FlowException( 'Internal error, please try again. If the error persists contact a salesforce admin.' ); }

        return orderIds[0];
    }

    private static void validateBooleanFlag(Boolean value, String flagName) {
        if (value == null || !value) {
            throw new IllegalArgumentException(
                'The flag \'' + flagName + '\' was not accepted.'
            );
        }
    }

    private static Date parseAcceptanceDate(String dateString) {
        try {
            return Date.valueOf(dateString);
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'acceptanceDate is not in valid format (expected YYYY-MM-DD): ' + dateString
            );
        }
    }
}