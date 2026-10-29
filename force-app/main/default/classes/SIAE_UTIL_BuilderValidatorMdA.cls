/**
 * @description : Fluent builder that prices a single MdA scenario through
 *                RevSalesTrxn.PlaceSalesTransactionExecutor and asserts the resulting
 *                price fields on the persisted QuoteLineItem.
 *                Prices are not returned by the executor: the response only carries the
 *                Quote id, so they are read back from the QuoteLineItem written by the
 *                SIAE_POSH_PricingMdAPlan post-hook.
 * @author      : Domenico Del Prete - ddelprete.consulente@siae.it
 **/
@isTest
public class SIAE_UTIL_BuilderValidatorMdA {

    public class BuilderValidatorException extends Exception {}

    public enum PriceField {
        TOTAL_DA,
        DIRITTI_CONNESSI,
        SCONTO_AC_DDA,
        SCONTO_AC_DC,
        TOTALE_SCONTO_AC_DDA,
        TOTALE_SCONTO_AC_DC,
        QUOTA_AC
    }

    private static final Map<PriceField, String> FIELD_NAME_BY_PRICE_FIELD = new Map<PriceField, String>{
        PriceField.TOTAL_DA => 'SIAE_TotalDA__c',
        PriceField.DIRITTI_CONNESSI => 'SIAE_DirittiConnessi__c',
        // SCONTO_AC_* are the discount rates applied by the agreement, as fractions
        // (0.27 = 27%); TOTALE_SCONTO_AC_* are the resulting discount amounts in currency,
        // which are what the "Sconto AC DDA"/"Sconto AC DC" columns of NRT-PROD.xlsx carry.
        PriceField.SCONTO_AC_DDA => 'SIAE_DDADiscountPercent__c',
        PriceField.SCONTO_AC_DC => 'SIAE_DCDiscountPercent__c',
        PriceField.TOTALE_SCONTO_AC_DDA => 'SIAE_TotalDiscountCADA__c',
        PriceField.TOTALE_SCONTO_AC_DC => 'SIAE_TotalDiscountCADC__c',
        PriceField.QUOTA_AC => 'SIAE_TotalCommercialAgreement__c'
    };

    private static final String GRAPH_ID = 'createQuote';
    private static final String QUOTE_REFERENCE_ID = 'refQuote';
    private static final String LINE_REFERENCE_ID = 'refSpazio1';
    private static final String METHOD_POST = 'POST';
    private static final String PICKLIST_DATA_TYPE = 'Picklist';

    // API values of the restricted picklist SIAE_TypeOfFlatRate__c: the pricing post-hook
    // SIAE_POSH_PricingMdAPlan matches them literally, so the labels ('FLAT AUDIO',
    // 'FLAT AUDIO-VIDEO') would silently route the scenario to the wrong pricing branch.
    private static final Set<String> FLAT_RATE_API_VALUES = new Set<String>{
        'FLAT_AUDIO',
        'FLAT_AUDIO_VIDEO'
    };

    // Neutral fixed values: the priced scenarios never vary these Quote fields, which the
    // digital channel payload carries alongside the ones that drive pricing.
    private static final String QUOTE_NAME = 'MdA Price Validation';
    private static final String QUOTE_LOCAL_NAME = 'MdA Price Validation';
    private static final String QUOTE_EGON_CIV_ID = '000001';
    private static final String QUOTE_STATUS = 'Draft';

    private Id productId;
    private Date startDate;
    private Date endDate;
    private String coverage;
    private String commercialAgreementCode;
    private String flatRateType;
    private final Map<String, String> valueByAttributeCode = new Map<String, String>();

    private QuoteLineItem pricedLineItem;

    /**
     * @description Registers the product priced by this scenario.
     * @param productId Id of the Product2 to price.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA addProductById(Id productId) {
        this.productId = productId;
        return this;
    }

    /**
     * @description Registers a product attribute of the scenario. Picklist attributes are
     * resolved to an AttributePicklistValue id, free attributes keep the textual value.
     * @param attributeCode Code of the AttributeDefinition.
     * @param attributeValue Textual value of the attribute.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA addAttribute(String attributeCode, String attributeValue) {
        this.valueByAttributeCode.put(attributeCode, attributeValue);
        return this;
    }

    /**
     * @description Sets the start date of Quote and QuoteLineItem.
     * @param startDate Start date of the priced period.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA withStartDate(Date startDate) {
        this.startDate = startDate;
        return this;
    }

    /**
     * @description Sets the end date of the QuoteLineItem.
     * @param endDate End date of the priced period.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA withEndDate(Date endDate) {
        this.endDate = endDate;
        return this;
    }

    /**
     * @description Sets SIAE_TypeOfCoverage__c on the QuoteLineItem.
     * @param coverage Coverage type of the licence.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA withCoverage(String coverage) {
        this.coverage = coverage;
        return this;
    }

    /**
     * @description Sets SIAE_CommercialAgreementCode__c on the QuoteLineItem.
     * @param commercialAgreementCode Code of the commercial agreement.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA withCommercialAgreement(String commercialAgreementCode) {
        this.commercialAgreementCode = commercialAgreementCode;
        return this;
    }

    /**
     * @description Sets SIAE_TypeOfFlatRate__c on the QuoteLineItem.
     * @param flatRateType Flat rate type of the licence, as the API value of the restricted
     * picklist (FLAT_AUDIO, FLAT_AUDIO_VIDEO), not as its label.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA withFlatRate(String flatRateType) {
        if (!FLAT_RATE_API_VALUES.contains(flatRateType)) {
            throw new BuilderValidatorException(
                'Valore SIAE_TypeOfFlatRate__c non riconosciuto: ' + flatRateType
                + '. Valori ammessi (API, non label): ' + FLAT_RATE_API_VALUES + '.'
            );
        }
        this.flatRateType = flatRateType;
        return this;
    }

    /**
     * @description Asserts the expected value of a price field on the priced QuoteLineItem,
     * running the sales transaction on the first call only.
     * @param field Price field to assert.
     * @param expectedValue Expected value, as text.
     * @return This builder, for chaining.
     */
    public SIAE_UTIL_BuilderValidatorMdA assertPrice(PriceField field, String expectedValue) {
        QuoteLineItem lineItem = priceScenario();
        String fieldName = FIELD_NAME_BY_PRICE_FIELD.get(field);

        System.assertEquals(
            Decimal.valueOf(expectedValue),
            (Decimal) lineItem.get(fieldName),
            'Prezzo atteso diverso sul campo ' + fieldName + '.'
        );
        return this;
    }

    /**
     * @description Runs the sales transaction once and caches the resulting QuoteLineItem.
     * @return The priced QuoteLineItem.
     */
    private QuoteLineItem priceScenario() {
        if (this.pricedLineItem != null) {
            return this.pricedLineItem;
        }

        RevSalesTrxn.PlaceSalesTransactionResponse response =
            RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                buildGraphRequest(),
                RevSalesTrxn.PricingPreferenceEnum.Force,
                RevSalesTrxn.ConfigurationExecutionEnum.Skip,
                buildConfigurationOptions(),
                null
            );

        if (response.isSuccess != true) {
            // errorResponse can be null on failure: serializing it unguarded would raise a
            // NullPointerException instead of the domain exception the callers expect.
            String errorDetail = response.errorResponse == null
                ? '(no errorResponse)'
                : JSON.serialize(response.errorResponse);
            throw new BuilderValidatorException(
                'PlaceSalesTransactionExecutor failed: ' + errorDetail
                + ' (salesTransactionId: ' + response.salesTransactionId + ')'
            );
        }

        List<QuoteLineItem> lineItems = byQuoteId(response.salesTransactionId);
        if (lineItems.size() != 1) {
            throw new BuilderValidatorException(
                'Expected exactly 1 QuoteLineItem for Quote ' + response.salesTransactionId
                + ', found ' + lineItems.size() + '.'
            );
        }
        this.pricedLineItem = lineItems[0];
        return this.pricedLineItem;
    }

    /**
     * @description Builds the Quote/QuoteLineItem/QuoteLineItemAttribute graph of the scenario.
     * @return The graph request accepted by PlaceSalesTransactionExecutor.
     */
    private RevSalesTrxn.GraphRequest buildGraphRequest() {
        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>{
                new RevSalesTrxn.RecordWithReferenceRequest(QUOTE_REFERENCE_ID, buildQuoteResource()),
                new RevSalesTrxn.RecordWithReferenceRequest(LINE_REFERENCE_ID, buildLineResource())
            };

        for (String attributeCode : this.valueByAttributeCode.keySet()) {
            records.add(
                new RevSalesTrxn.RecordWithReferenceRequest(
                    LINE_REFERENCE_ID + '-' + attributeCode,
                    buildAttributeResource(attributeCode, this.valueByAttributeCode.get(attributeCode))
                )
            );
        }

        return new RevSalesTrxn.GraphRequest(GRAPH_ID, records);
    }

    /**
     * @description Builds the Quote record of the graph.
     * @return The Quote record resource.
     */
    private RevSalesTrxn.RecordResource buildQuoteResource() {
        RevSalesTrxn.RecordResource quoteResource =
            new RevSalesTrxn.RecordResource(Quote.SObjectType, METHOD_POST);
        quoteResource.fieldValues = new Map<String, Object>{
            'Name' => QUOTE_NAME,
            'StartDate' => isoDate(this.startDate),
            'Status' => QUOTE_STATUS,
            'SIAE_LocalName__c' => QUOTE_LOCAL_NAME,
            'SIAE_IdEgonCiv__c' => QUOTE_EGON_CIV_ID
        };
        return quoteResource;
    }

    /**
     * @description Builds the QuoteLineItem record of the graph.
     * @return The QuoteLineItem record resource.
     */
    private RevSalesTrxn.RecordResource buildLineResource() {
        RevSalesTrxn.RecordResource lineResource =
            new RevSalesTrxn.RecordResource(QuoteLineItem.SObjectType, METHOD_POST);

        Map<String, Object> fieldValues = new Map<String, Object>{
            'QuoteId' => '@{' + QUOTE_REFERENCE_ID + '.id}',
            'Product2Id' => this.productId,
            'Quantity' => '1',
            'StartDate' => isoDate(this.startDate),
            'EndDate' => isoDate(this.endDate),
            'SIAE_TypeOfCoverage__c' => this.coverage
        };
        if (String.isNotBlank(this.commercialAgreementCode)) {
            fieldValues.put('SIAE_CommercialAgreementCode__c', this.commercialAgreementCode);
        }
        if (String.isNotBlank(this.flatRateType)) {
            fieldValues.put('SIAE_TypeOfFlatRate__c', this.flatRateType);
        }

        lineResource.fieldValues = fieldValues;
        return lineResource;
    }

    /**
     * @description Builds a QuoteLineItemAttribute record of the graph.
     * @param attributeCode Code of the AttributeDefinition.
     * @param attributeValue Textual value of the attribute.
     * @return The QuoteLineItemAttribute record resource.
     */
    private RevSalesTrxn.RecordResource buildAttributeResource(String attributeCode, String attributeValue) {
        AttributeDefinition definition = attributeByCode(attributeCode);

        Map<String, Object> fieldValues = new Map<String, Object>{
            'QuoteLineItemId' => '@{' + LINE_REFERENCE_ID + '.id}',
            'AttributeDefinitionId' => definition.Id
        };
        if (PICKLIST_DATA_TYPE.equalsIgnoreCase(definition.DataType)) {
            fieldValues.put(
                'AttributePicklistValueId',
                attributePicklistValueId(definition.Id, attributeValue)
            );
        } else {
            fieldValues.put('AttributeValue', attributeValue);
        }

        RevSalesTrxn.RecordResource attributeResource =
            new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.SObjectType, METHOD_POST);
        attributeResource.fieldValues = fieldValues;
        return attributeResource;
    }

    /**
     * @description Builds the configuration options of the sales transaction, matching the
     * payload used by the digital channel.
     * @return The configuration options input.
     */
    private RevSalesTrxn.ConfigurationOptionsInput buildConfigurationOptions() {
        RevSalesTrxn.ConfigurationOptionsInput options = new RevSalesTrxn.ConfigurationOptionsInput();
        options.validateProductCatalog = true;
        options.validateAmendRenewCancel = true;
        options.executeConfigurationRules = true;
        options.addDefaultConfiguration = true;
        return options;
    }

    /**
     * @description Formats a date as the ISO string expected by the sales transaction payload,
     * independently of the running user locale.
     * @param value Date to format.
     * @return The date as yyyy-MM-dd.
     */
    private static String isoDate(Date value) {
        return String.valueOf(value.year()).leftPad(4, '0')
            + '-' + String.valueOf(value.month()).leftPad(2, '0')
            + '-' + String.valueOf(value.day()).leftPad(2, '0');
    }

    public static Product2 byCode(String productCode) {
        List<Product2> listOfProduct = new List<Product2>([SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode =: productCode LIMIT 1]);
        if (listOfProduct.isEmpty()) return null;
        return listOfProduct[0];
    }

    
    public class QuoteLineItemNotFoundException extends Exception {}

    /**
     * @description Returns the QuoteLineItem records for the given Quote, including
     * the price fields persisted by the SIAE_POSH_PricingMdAPlan post-hook.
     * @param quoteId Id of the Quote whose QuoteLineItem records are returned.
     * @return List of matching QuoteLineItem records (NetUnitPrice, TotalLineAmount,
     * SIAE_TotalDA__c, SIAE_DirittiConnessi__c, SIAE_DDADiscountPercent__c,
     * SIAE_DCDiscountPercent__c, SIAE_TotalCommercialAgreement__c,
     * SIAE_TotalDiscountCADA__c, SIAE_TotalDiscountCADC__c).
     */
    private static List<QuoteLineItem> byQuoteId(Id quoteId) {
        List<QuoteLineItem> lineItems = [
            SELECT NetUnitPrice,
                   TotalLineAmount,
                   SIAE_TotalDA__c,
                   SIAE_DirittiConnessi__c,
                   SIAE_DDADiscountPercent__c,
                   SIAE_DCDiscountPercent__c,
                   SIAE_TotalCommercialAgreement__c,
                   SIAE_TotalDiscountCADA__c,
                   SIAE_TotalDiscountCADC__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ];

        // A missing QuoteLineItem after PlaceSalesTransactionExecutor signals a failed
        // test scenario, not a silent empty state.
        if (lineItems.isEmpty()) {
            throw new QuoteLineItemNotFoundException(
                'No QuoteLineItem found for Quote ' + quoteId
            );
        }

        return lineItems;
    }

    /**
     * @description Returns the AttributeDefinition matching the given code.
     * @param attributeDefinitionCode Code of the attribute definition.
     * @return The matching AttributeDefinition (Id, Code, DataType, PicklistId).
     */
    public static AttributeDefinition attributeByCode(String attributeDefinitionCode) {
        return [
            SELECT Id, Code, DataType, PicklistId
            FROM AttributeDefinition
            WHERE Code = :attributeDefinitionCode
            LIMIT 1
        ];
    }

    /**
     * @description Returns the AttributePicklistValue id matching the given textual
     * value, for a picklist-type attribute definition.
     * @param attributeDefinitionId Id of the attribute definition.
     * @param value Textual picklist value to resolve.
     * @return Id of the matching AttributePicklistValue.
     */
    public static Id attributePicklistValueId(Id attributeDefinitionId, String value) {
        AttributeDefinition attrDef = [
            SELECT Id, PicklistId
            FROM AttributeDefinition
            WHERE Id = :attributeDefinitionId
            LIMIT 1
        ];

        AttributePicklistValue picklistValue = [
            SELECT Id
            FROM AttributePicklistValue
            WHERE PicklistId = :attrDef.PicklistId AND Value = :value
            LIMIT 1
        ];

        return picklistValue.Id;
    }
}