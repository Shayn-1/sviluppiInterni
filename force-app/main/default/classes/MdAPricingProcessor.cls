/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 10-28-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public class MdAPricingProcessor {
    private static final String FIELD_TOTAL_DA = 'SIAE_TotalDA__c';
    private static final String FIELD_TYPE_OF_FLAT_RATE = 'SIAE_TypeOfFlatRate__c';
    private static final String FIELD_FLAT_AUDIO = 'SIAE_FlatAudio__c';
    private static final String FIELD_FLAT_VIDEO = 'SIAE_FlatVideo__c';
    private static final String FIELD_COEFF_MAGG_MQ = 'SIAE_CoeffMaggiorazioneMQ__c';
    private static final String FIELD_COEFF_AREE_EST = 'SIAE_CoeffAreeEsterne__c';
    private static final String FIELD_COEFF_STAG = 'SIAE_CoeffStagionalita__c';
    private static final String FIELD_NET_TOTAL_PRICE = 'NetTotalPrice';
    private static final String FIELD_NET_UNIT_PRICE = 'NetUnitPrice';
    private static final String FIELD_TOTAL_LINE_AMOUNT = 'TotalLineAmount';
    private static final String FIELD_UNIT_PRICE = 'UnitPrice';
    private static final String FIELD_SUBTOTAL = 'Subtotal';
    private static final String FIELD_TOTAL_AMOUNT = 'TotalAmount';
    private static final String COVERAGE_ANNUALE = 'Annuale';
    private static final String FEE_TYPE_SI_DDA = 'SI_DDA';
    private static final String FEE_TYPE_SI_DC  = 'SI_DC';

    
    /**
     * Applica il pricing MdA (DDA, accordo commerciale, DC, voci incasso) al modello RCA.
     * I risultati sono scritti in attributeToUpdate di item e transazioni; la lettura e la
     * scrittura del contesto restano a carico dell'entry point.
     */
    public static void process(RCASalesTransaction ctxResult) {
        if (ctxResult == null || ctxResult.items.isEmpty()) {
            return;
        }

        Set<String> setOfProdId = new Set<String>();
        Set<String> setOfCommercialCode = new Set<String>();
        for (RCASalesTransaction.ItemNode node : ctxResult.items) {
            setOfProdId.add(node.productId);
            setOfCommercialCode.add(node.commercialCode);
        }
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>(
            [SELECT Id, Family, ProductCode FROM Product2 WHERE Id IN :setOfProdId]
            );
        Set<String> setOfProductFamily = new Set<String>();
        Set<String> setOfProductCode = new Set<String>();
        for(Product2 prod : mapProductIdProduct.values()){
            setOfProductFamily.add(prod.Family);
            setOfProductCode.add(prod.ProductCode);
        }

        MdAPricingConfiguration.ConfigurationIndex pricingConfigurations =
            MdAPricingConfiguration.load(toIdSet(setOfProdId));
        
		// VOCI INCASSO DDA
        Map<String, List<PricingPaymentItem>> paymentItemsDDAByLineItemId =
            SIAE_UTIL_VoceIncassoEngine.calculateByLineItems(
                ctxResult.items,
                mapProductIdProduct,
                new Set<String>{ 'DDA' },
                pricingConfigurations
            );
        
        //System.debug('Payment Items DDA --> ' + JSON.serializePretty(paymentItemsDDAByLineItemId));
        
        /*-----------------------------------------------------------------*/        
        
        SIAE_UTIL_CalculateCommercialQuote.CommercialAgreementIndex commercialAgreementIndex =
            SIAE_UTIL_CalculateCommercialQuote.loadCommercialAgreements(setOfCommercialCode, setOfProductFamily);
        List<SIAE_AttributeConfiguration__mdt> listOfAttributeConfig = new List<SIAE_AttributeConfiguration__mdt>([SELECT Id, DeveloperName, SIAE_AttributeList__c,SIAE_AttributeListDC__c
                                                                                                                    FROM SIAE_AttributeConfiguration__mdt
                                                                                                                    WHERE DeveloperName =: 'Mda']);
        
        // VOCI INCASSO QUOTA ASSOCIATIVA E CALCOLO
        Map<String, Decimal> quotaAssociativaByLineItemId = new Map<String, Decimal>();
        Map<String, Decimal> ddaDiscountPercentByLineItemId = new Map<String, Decimal>();

        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            SIAE_UTIL_CalculateCommercialQuote.CalculationResult wrCalculation =
                new SIAE_UTIL_CalculateCommercialQuote.CalculationResult();
        
            /*
             * Default a 0 per evitare valori residui nel context
             * quando non viene applicato alcun accordo commerciale.
             */
            itemNode.attributeToUpdate.put('SIAE_TotalCommercialAgreement__c', 0);
            itemNode.attributeToUpdate.put('SIAE_DCDiscountPercent__c', 0);
            itemNode.attributeToUpdate.put('SIAE_DDADiscountPercent__c', 0);
            itemNode.attributeToUpdate.put('SIAE_TotalDiscountCADA__c', 0);
            itemNode.attributeToUpdate.put('SIAE_TotalDiscountCADC__c', 0);


            Decimal numberOfDevice = calculateNumberOfDevice(
                itemNode.attributeValueByCode,
                listOfAttributeConfig[0]
            );

            Decimal totalDABeforeAgreement = calculateTotalDA(itemNode, pricingConfigurations);
            Decimal totalDA = totalDABeforeAgreement;

            if (
                !String.isBlank(itemNode.commercialCode) &&
                mapProductIdProduct.containsKey(itemNode.productId) &&
                !String.isBlank(mapProductIdProduct.get(itemNode.productId).Family)
            ) {
                String key = itemNode.commercialCode + '|' + mapProductIdProduct.get(itemNode.productId).Family;

                Date effectiveDate = RCAValueConverter.asDate(itemNode.effectiveFrom);
                SIAE_AccordoCommerciale__c commercialAgreement =
                    commercialAgreementIndex.resolve(key, effectiveDate);

                Map<String, SIAE_AccordoCommerciale__c> agreementForLineItem =
                    new Map<String, SIAE_AccordoCommerciale__c>();
                if (commercialAgreement != null) {
                    agreementForLineItem.put(key, commercialAgreement);
                }

                wrCalculation = SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                    key,
                    agreementForLineItem,
                    numberOfDevice,
                    totalDABeforeAgreement
                );

                totalDA = wrCalculation.compensoTotaleScontato != null
                    ? RCAValueConverter.roundMoney(wrCalculation.compensoTotaleScontato)
                    : totalDABeforeAgreement;

                itemNode.netTotalPrice = totalDA;

                itemNode.discountDc = wrCalculation.percentualeScontoDC != null
                    ? wrCalculation.percentualeScontoDC
                    : 0;
        
                Decimal ddaDiscountPercent = wrCalculation.riduzioneCompensoBasePercent != null
                    ? wrCalculation.riduzioneCompensoBasePercent
                    : 0;

                if (String.isNotBlank(itemNode.lineItemId) && ddaDiscountPercent != 0) {
                    ddaDiscountPercentByLineItemId.put(itemNode.lineItemId, ddaDiscountPercent);
                }

                Decimal dcDiscountPercent = wrCalculation.percentualeScontoDC != null
                    ? wrCalculation.percentualeScontoDC
                    : 0;
        
                Decimal totalCommercialAgreement = wrCalculation.quota != null
                    ? wrCalculation.quota.setScale(2, RoundingMode.HALF_UP)
                    : 0;

                itemNode.commercialAgreementQuota = totalCommercialAgreement;

                Decimal totalDiscountCADA =
                    wrCalculation.compensoTotaleInput != null &&
                    wrCalculation.compensoTotaleScontato != null
                        ? (wrCalculation.compensoTotaleInput - wrCalculation.compensoTotaleScontato)
                            .setScale(2, RoundingMode.HALF_UP)
                        : 0;

                itemNode.attributeToUpdate.put('SIAE_DDADiscountPercent__c', ddaDiscountPercent);
                itemNode.attributeToUpdate.put('SIAE_DCDiscountPercent__c', dcDiscountPercent);
                itemNode.attributeToUpdate.put('SIAE_TotalCommercialAgreement__c', totalCommercialAgreement);
                itemNode.attributeToUpdate.put('SIAE_TotalDiscountCADA__c', totalDiscountCADA);
        
                if (
                    String.isNotBlank(itemNode.lineItemId) &&
                    wrCalculation.quota != null &&
                    wrCalculation.quota != 0
                ) {
                    quotaAssociativaByLineItemId.put(itemNode.lineItemId, wrCalculation.quota);
                }
        
                itemNode.attributeToUpdate.put(FIELD_NET_TOTAL_PRICE, itemNode.netTotalPrice);
                itemNode.attributeToUpdate.put(FIELD_NET_UNIT_PRICE, itemNode.netTotalPrice);
                itemNode.attributeToUpdate.put(FIELD_TOTAL_LINE_AMOUNT, itemNode.netTotalPrice);
                itemNode.attributeToUpdate.put(FIELD_UNIT_PRICE, itemNode.netTotalPrice);
            }
        
            Decimal totalDAWithCommercialAgreement = RCAValueConverter.roundMoney(totalDA + itemNode.commercialAgreementQuota);
            itemNode.attributeToUpdate.put(FIELD_TOTAL_DA, totalDAWithCommercialAgreement);

            if (SIAE_UTIL_PricingMdA.isFlatRateSelected(itemNode.typeOfFlatRate)) {
                applyStandardItemTotals(itemNode, totalDA);
            }
        }
        
        Map<String, List<PricingPaymentItem>> paymentItemsQAByLineItemId =
            SIAE_UTIL_VoceIncassoEngine.calculateQuotaAssociativaByLineItems( 
                ctxResult.items,
                quotaAssociativaByLineItemId
            );
        
        //System.debug('Payment Items QA --> ' + JSON.serializePretty(paymentItemsQAByLineItemId));
        
        /*----------------------------------------------------------------------------------------*/
        
        /*for(RCASalesTransaction.ItemNode itemNode : ctxResult.items){
            SIAE_UTIL_CalculateCommercialQuote.CalculationResult wrCalculation = new SIAE_UTIL_CalculateCommercialQuote.CalculationResult();
            Decimal numberOfDevice = calculateNumberOfDevice(itemNode.attributeValueByCode, listOfAttributeConfig[0]);
            System.debug('item node: ' + itemNode.commercialCode);
            if(!String.isBlank(itemNode.commercialCode) && mapProductIdProduct.containsKey(itemNode.productId) && !String.isBlank(mapProductIdProduct.get(itemNode.productId).Family)){
                String key = itemNode.commercialCode + '|' + mapProductIdProduct.get(itemNode.productId).Family;
                wrCalculation = SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(key , mapKeyAccordoCommerciale, numberOfDevice, itemNode.netTotalPrice);
                itemNode.netTotalPrice = wrCalculation.compensoTotaleScontato.setScale(2, RoundingMode.HALF_UP);
                itemNode.discountDc = wrCalculation.percentualeScontoDC != null ? wrCalculation.percentualeScontoDC : 0;
                PricingPaymentItem wrPaymentItem = new PricingPaymentItem();
                wrPaymentItem.itemCode = wrCalculation.voceQuota;
                wrPaymentItem.amount = String.valueOf(wrCalculation.quota.setScale(2).format());
                System.debug('wrPaymentItem: ' + wrPaymentItem);
                itemNode.paymentWrapper.paymentItems.add(wrPaymentItem);
                itemNode.attributeToUpdate.put(FIELD_NET_TOTAL_PRICE, itemNode.netTotalPrice);
                itemNode.attributeToUpdate.put(FIELD_NET_UNIT_PRICE, itemNode.netTotalPrice);
                itemNode.attributeToUpdate.put('SIAE_PaymentItems__c', JSON.serialize(itemNode.paymentWrapper));
                itemNode.attributeToUpdate.put(FIELD_TOTAL_LINE_AMOUNT, itemNode.netTotalPrice);
                //itemNode.attributeToUpdate.put('TotalRoundedLineAmount', itemNode.netTotalPrice.setScale(2).format());
                itemNode.attributeToUpdate.put(FIELD_UNIT_PRICE, itemNode.netTotalPrice);
            }
        }*/
        
        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            Product2 prod = mapProductIdProduct.get(itemNode.productId);
            if (prod != null) {
                if ('SIAE-PROD-AFFITTI-BREVI'.equals(prod.ProductCode)) {
                    SIAE_AttributeConfiguration__mdt config = !listOfAttributeConfig.isEmpty() ? listOfAttributeConfig[0] : null;
                    String fascia = classifyAffittiBrevi(itemNode.attributeValueByCode, config);
                    if (fascia != null) {
                        itemNode.attributeValueByCode.put('SIAE-ATTR-FASCIA-TARIFFA', fascia);
                    }
                }
            }
        }
        
        SIAE_DTO_DirittiConnessiResult wrapperDirittiConnessi =
            SIAE_UTIL_DirittiConnessiEngine.calculate(
                ctxResult.items,
                setOfProductCode,
                mapProductIdProduct
            );
        
        System.debug('Diritti Connessi --> '+ JSON.serializePretty(wrapperDirittiConnessi));
        
        // VOCI INCASSO DC
        Map<String, List<PricingPaymentItem>> paymentItemsDCByLineItemId =
            SIAE_UTIL_VoceIncassoEngine.calculateDirittiConnessiByLineItems(
                wrapperDirittiConnessi
            );
        
        System.debug('Payment Items DC --> ' + JSON.serializePretty(paymentItemsDCByLineItemId));
        
        /*---------------------------------------------------------------*/
        
        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            itemNode.attributeValueByCode.remove('SIAE-ATTR-FASCIA-TARIFFA');
        }
        
        Map<String, SIAE_DTO_DirittiConnessiResult.LicenzaDetail> dettagliByLineItemId = new Map<String, SIAE_DTO_DirittiConnessiResult.LicenzaDetail>();
        for (SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail : wrapperDirittiConnessi.dettagliPerOrderItem) {
            if (String.isNotBlank(detail.orderItemId)) {
                dettagliByLineItemId.put(detail.orderItemId, detail);
            }
        }
        
        //VOCE INCASSO SPESA ISTRUTTORIA
        Map<String, List<PricingPaymentItem>> supplementarySiItemsByLineItemId =
            SIAE_UTIL_VoceIncassoEngine.addSupplementarySiItemsByLineItem(
                paymentItemsDDAByLineItemId,
                paymentItemsDCByLineItemId
            );

        /*
         * Lo sconto DDA viene applicato SOLO ORA, dopo aver calcolato i PricingPaymentItem
         * supplementari SI_DDA/SI_DC: la eligibility-check di SI_DDA (hasValidPaymentItems)
         * deve valutare gli importi DDA pre-sconto, altrimenti uno sconto del 100%
         * azzererebbe i PricingPaymentItem DDA e farebbe saltare la generazione di SI_DDA.
         */
        paymentItemsDDAByLineItemId = SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
            paymentItemsDDAByLineItemId,
            ddaDiscountPercentByLineItemId
        );

        //VOCI INCASSO PAYMENTITEM
        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            List<PricingPaymentItem> qa  = paymentItemsQAByLineItemId.get(itemNode.lineItemId);
            List<PricingPaymentItem> dda = paymentItemsDDAByLineItemId.get(itemNode.lineItemId);
            List<PricingPaymentItem> dc  = paymentItemsDCByLineItemId.get(itemNode.lineItemId);
            List<PricingPaymentItem> si  = supplementarySiItemsByLineItemId.get(itemNode.lineItemId);
        
            if (qa != null && !qa.isEmpty()) {
                itemNode.paymentWrapper.paymentItems.addAll(qa);
            }
        
            if (dda != null && !dda.isEmpty()) {
                itemNode.paymentWrapper.paymentItems.addAll(dda);
            }
        
            if (dc != null && !dc.isEmpty()) {
                itemNode.paymentWrapper.paymentItems.addAll(dc);
            }
        
            if (si != null && !si.isEmpty()) {
                itemNode.paymentWrapper.paymentItems.addAll(si);
            }
        }

        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            SIAE_DTO_DirittiConnessiResult.LicenzaDetail dettaglioDC =
                dettagliByLineItemId.get(itemNode.lineItemId);
        
            Decimal dirittiConnessi = 0;

            if (dettaglioDC != null && dettaglioDC.subtotalePreSconto != null && dettaglioDC.subtotale != null) {
                Decimal totalDiscountCADC =
                    (dettaglioDC.subtotalePreSconto - dettaglioDC.subtotale)
                        .setScale(2, RoundingMode.HALF_UP);

                itemNode.attributeToUpdate.put(
                    'SIAE_TotalDiscountCADC__c',
                    totalDiscountCADC
                );
            }

            if (dettaglioDC != null && dettaglioDC.subtotale != null) {
                dirittiConnessi = dettaglioDC.subtotale;
            }

            // Ripartizione spese di istruttoria: SI_DDA -> TotalDA, SI_DC -> DirittiConnessi.
            // Le voci istruttoria esistono per riga solo quando ci sono rispettivamente
            // diritti d'autore (SI_DDA) o diritti connessi calcolati (SI_DC).
            List<PricingPaymentItem> supplementarySiItems =
                supplementarySiItemsByLineItemId.get(itemNode.lineItemId);
            Decimal siDdaFees = sumPaymentItemAmountsByType(supplementarySiItems, FEE_TYPE_SI_DDA);
            Decimal siDcFees  = sumPaymentItemAmountsByType(supplementarySiItems, FEE_TYPE_SI_DC);

            // Diritti Connessi comprensivi dell'istruttoria DC (solo se DC effettivamente calcolati).
            Decimal dirittiConnessiFinale = RCAValueConverter.roundMoney(dirittiConnessi + siDcFees);

            // Scrittura sempre esplicita (anche a 0, come per FIELD_TOTAL_DA): quando il prodotto
            // non ha DC applicabili (nessuna SIAE_DirittiConnessiConfig__mdt o CalculationEnabled=false),
            // dettaglioDC resta null e senza questa riga il campo non verrebbe mai valorizzato,
            // restando blank sull'OrderItem e facendo fallire SIAE_REST_SalvaScheda (tariffa.dc mancante).
            itemNode.attributeToUpdate.put(
                'SIAE_DirittiConnessi__c',
                dirittiConnessiFinale
            );

            // TotalDA comprensivo dell'istruttoria DDA (il valore base è già stato impostato nel primo loop).
            Decimal currentTotalDA = (Decimal) itemNode.attributeToUpdate.get(FIELD_TOTAL_DA);
            Decimal totalDAFinale = RCAValueConverter.roundMoney((currentTotalDA == null ? 0 : currentTotalDA) + siDdaFees);
            itemNode.attributeToUpdate.put(FIELD_TOTAL_DA, totalDAFinale);

            // Totalone ricostruito dai sotto-campi: la quota accordo NON va riaggiunta (già dentro TotalDA).
            itemNode.netTotalPrice = RCAValueConverter.roundMoney(totalDAFinale + dirittiConnessiFinale);

            itemNode.attributeToUpdate.put(FIELD_NET_TOTAL_PRICE, itemNode.netTotalPrice);
            itemNode.attributeToUpdate.put(FIELD_NET_UNIT_PRICE, itemNode.netTotalPrice);
            itemNode.attributeToUpdate.put(FIELD_TOTAL_LINE_AMOUNT, itemNode.netTotalPrice);
            itemNode.attributeToUpdate.put(FIELD_UNIT_PRICE, itemNode.netTotalPrice);
        
            if (!itemNode.paymentWrapper.paymentItems.isEmpty()) {
                itemNode.attributeToUpdate.put(
                    'SIAE_PaymentItems__c',
                    JSON.serialize(itemNode.paymentWrapper)
                );
            }
        
        }
        
        if (hasAnyFlatRateSelected(ctxResult.items)) {
            addSalesTransactionStandardTotalUpdates(ctxResult);
        }
    }
    
    @TestVisible
    private static void applyStandardItemTotals(RCASalesTransaction.ItemNode itemNode, Decimal totalAmount) {
        if (itemNode == null) {
            return;
        }

        Decimal safeTotalAmount = RCAValueConverter.roundMoney(totalAmount);
        itemNode.netTotalPrice = safeTotalAmount;
        itemNode.attributeToUpdate.put(FIELD_NET_TOTAL_PRICE, safeTotalAmount);
        itemNode.attributeToUpdate.put(FIELD_NET_UNIT_PRICE, safeTotalAmount);
        itemNode.attributeToUpdate.put(FIELD_TOTAL_LINE_AMOUNT, safeTotalAmount);
        itemNode.attributeToUpdate.put(FIELD_UNIT_PRICE, safeTotalAmount);
    }

    @TestVisible
    private static Boolean hasAnyFlatRateSelected(List<RCASalesTransaction.ItemNode> items) {
        if (items == null || items.isEmpty()) {
            return false;
        }

        for (RCASalesTransaction.ItemNode itemNode : items) {
            if (SIAE_UTIL_PricingMdA.isFlatRateSelected(itemNode.typeOfFlatRate)) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static void addSalesTransactionStandardTotalUpdates(
        RCASalesTransaction ctxResult
    ) {
        if (
            ctxResult == null ||
            ctxResult.transactions == null ||
            ctxResult.transactions.isEmpty() ||
            ctxResult.items == null ||
            ctxResult.items.isEmpty()
        ) {
            return;
        }

        Map<String, Decimal> totalByTransactionKey = new Map<String, Decimal>();

        for (RCASalesTransaction.ItemNode itemNode : ctxResult.items) {
            if (itemNode == null) {
                continue;
            }

            String transactionKey = itemNode.transactionKey;

            if (String.isBlank(transactionKey)) {
                continue;
            }

            Decimal lineTotal = itemNode.netTotalPrice == null ? 0 : itemNode.netTotalPrice;
            Decimal currentTotal = totalByTransactionKey.containsKey(transactionKey)
                ? totalByTransactionKey.get(transactionKey)
                : 0;

            totalByTransactionKey.put(transactionKey, currentTotal + lineTotal);
        }

        for (RCASalesTransaction.TransactionNode transactionNode : ctxResult.transactions) {
            if (transactionNode == null) {
                continue;
            }

            String transactionKey = transactionNode.transactionKey;

            if (String.isBlank(transactionKey) || !totalByTransactionKey.containsKey(transactionKey)) {
                continue;
            }

            Decimal transactionTotal = RCAValueConverter.roundMoney(totalByTransactionKey.get(transactionKey));
            transactionNode.attributeToUpdate.put(FIELD_SUBTOTAL, transactionTotal);
            transactionNode.attributeToUpdate.put(FIELD_TOTAL_AMOUNT, transactionTotal);

        }
    }


   @TestVisible
    private static Decimal calculateTotalDA(
        RCASalesTransaction.ItemNode itemNode,
        MdAPricingConfiguration.ConfigurationIndex pricingConfigurations
    ) {
        if (itemNode == null) {
            return 0;
        }
    
        if (!SIAE_UTIL_PricingMdA.isFlatRateSelected(itemNode.typeOfFlatRate)) {
            return SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
                itemNode.netTotalPrice,
                itemNode.typeOfFlatRate,
                itemNode.coeffMaggiorazioneMQ,
                itemNode.coeffAreeEsterne,
                itemNode.periodicityCoefficient
            );
        }
    
        Decimal flatBaseAmount = resolveFlatBaseAmount(itemNode);
    
        Decimal flatAmountWithCoefficients =
            SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
                flatBaseAmount,
                itemNode.typeOfFlatRate,
                itemNode.coeffMaggiorazioneMQ,
                itemNode.coeffAreeEsterne,
                itemNode.periodicityCoefficient
            );
    
        Decimal additionalFlatDeviceAmount = calculateAdditionalFlatDeviceAmount(
            itemNode,
            pricingConfigurations
        );
    
        return RCAValueConverter.roundMoney(flatAmountWithCoefficients + additionalFlatDeviceAmount);
    }

    @TestVisible
    private static Decimal resolveFlatBaseAmount(RCASalesTransaction.ItemNode itemNode) {
        if (itemNode == null) {
            return 0;
        }

        if (!SIAE_UTIL_PricingMdA.isFlatRateSelected(itemNode.typeOfFlatRate)) {
            return itemNode.netTotalPrice == null ? 0 : itemNode.netTotalPrice;
        }

        if ('FLAT_AUDIO'.equalsIgnoreCase(itemNode.typeOfFlatRate)) {
            return itemNode.flatAudioAmount == null ? 0 : itemNode.flatAudioAmount;
        }

        if ('FLAT_AUDIO_VIDEO'.equalsIgnoreCase(itemNode.typeOfFlatRate)) {
            return itemNode.flatVideoAmount == null ? 0 : itemNode.flatVideoAmount;
        }

        return itemNode.netTotalPrice == null ? 0 : itemNode.netTotalPrice;
    }

    @TestVisible
    private static Decimal calculateAdditionalFlatDeviceAmount(
        RCASalesTransaction.ItemNode itemNode,
        MdAPricingConfiguration.ConfigurationIndex pricingConfigurations
    ) {
        if (
            itemNode == null ||
            !SIAE_UTIL_PricingMdA.isFlatRateSelected(itemNode.typeOfFlatRate)
        ) {
            return 0;
        }

        SIAE_ConfigurazionePricing__c flatConfig = pricingConfigurations == null
            ? null
            : pricingConfigurations.resolve(
                toId(itemNode.productId),
                RCAValueConverter.asDate(itemNode.effectiveFrom)
            );

        if (flatConfig == null) {
            return 0;
        }

        return SIAE_UTIL_PricingMdA.calculateAdditionalFlatAmount(
            buildFlatCalculationSourceItem(itemNode),
            flatConfig
        );
    }


    @TestVisible
    private static Map<String, Object> buildFlatCalculationSourceItem(RCASalesTransaction.ItemNode itemNode) {
        Map<String, Object> sourceItem = new Map<String, Object>();
        List<Object> attributeNodes = new List<Object>();

        if (itemNode == null || itemNode.attributes == null) {
            sourceItem.put('SalesTransactionItemAttribute', attributeNodes);
            return sourceItem;
        }

        for (RCASalesTransaction.AttributeNode attrNode : itemNode.attributes) {
            if (attrNode == null) {
                continue;
            }

            attributeNodes.add(new Map<String, Object>{
                'AttributeDefinitionCode' => attrNode.attributeCode,
                'AttributeValue'          => attrNode.attributeValue,
                'SIAE_DeviceTotalPrice'   => attrNode.deviceTotalPrice
            });
        }

        sourceItem.put('SalesTransactionItemAttribute', attributeNodes);
        return sourceItem;
    }

    @TestVisible
    private static Decimal sumPaymentItemAmounts(List<PricingPaymentItem> paymentItems) {
        Decimal total = 0;
    
        if (paymentItems == null || paymentItems.isEmpty()) {
            return total;
        }
    
        for (PricingPaymentItem item : paymentItems) {
            if (item == null || (item.amount == null || String.isBlank(String.valueOf(item.amount)))) {
                continue;
            }
    
            try {
                String rawAmount = String.valueOf(item.amount).trim();
    
                if (rawAmount.contains(',') && rawAmount.contains('.')) {
                    rawAmount = rawAmount.replace('.', '').replace(',', '.');
                } else if (rawAmount.contains(',')) {
                    rawAmount = rawAmount.replace(',', '.');
                }
    
                total += Decimal.valueOf(rawAmount);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Errore parsing amount AdministrativeFees: ' + item.amount + ' - ' + e.getMessage()
                );
            }
        }

        return total.setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private static Decimal sumPaymentItemAmountsByType(List<PricingPaymentItem> paymentItems, String feeType) {
        if (paymentItems == null || paymentItems.isEmpty() || String.isBlank(feeType)) {
            return 0;
        }

        List<PricingPaymentItem> filtered = new List<PricingPaymentItem>();

        for (PricingPaymentItem item : paymentItems) {
            if (item != null && feeType.equalsIgnoreCase(item.type)) {
                filtered.add(item);
            }
        }

        return sumPaymentItemAmounts(filtered);
    }

    @TestVisible
    private static Boolean isCoperturaAnnuale(String typeCoverage) {
        return String.isBlank(typeCoverage) || COVERAGE_ANNUALE.equalsIgnoreCase(typeCoverage);
    }

    // dmlStatus è un campo di ogni tag dentro tagValue, non della riga esterna
    
    private static Decimal calculateNumberOfDevice(Map<String, String> attributeValueByCode, SIAE_AttributeConfiguration__mdt attributeConfig) {
        Set<String> attributeCodesToCheck = new Set<String>(attributeConfig.SIAE_AttributeList__c.split(';'));
        Decimal numberOfDevice = 0;
        for (String code : attributeCodesToCheck) {
            if (!attributeValueByCode.containsKey(code)) continue;
            Decimal parsed = SIAE_UTIL_PricingMdA.parseDecimal(attributeValueByCode.get(code));
            if (parsed != null) {
                numberOfDevice += parsed;
            }
        }
        return numberOfDevice;
    }
    
    @TestVisible
    private static String classifyAffittiBrevi(Map<String, String> attributeValueByCode, SIAE_AttributeConfiguration__mdt attributeConfig) {
        if (attributeConfig == null || String.isBlank(attributeConfig.SIAE_AttributeListDC__c)) {
            return '1 Stella'; 
        }

        Decimal totalDevices = 0;
        Set<String> deviceAttributes = new Set<String>(attributeConfig.SIAE_AttributeListDC__c.split(';'));
        for (String attrCode : deviceAttributes) {
            if (attributeValueByCode.containsKey(attrCode)) {
                Decimal deviceCount = SIAE_UTIL_PricingMdA.parseDecimal(attributeValueByCode.get(attrCode));
                if (deviceCount != null) {
                    totalDevices += deviceCount;
                }
            }
        }
        
        Decimal qta = SIAE_UTIL_PricingMdA.parseDecimal(attributeValueByCode.get('SIAE-ATTR-QTA'));
        if (qta == null) {
            qta = 0;
        }
        
        if (qta > 25) {
            return '2 Stelle';
        } else {
            if (totalDevices > 1) {
                return '2 Stelle';
            } else {
                return '1 Stella';
            }
        }
    }


    private static Set<Id> toIdSet(Set<String> productIds) {
        Set<Id> result = new Set<Id>();
        if (productIds == null) { return result; }
        for (String productId : productIds) {
            Id parsed = toId(productId);
            if (parsed != null) { result.add(parsed); }
        }
        return result;
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) { return null; }
        try { return (Id)value; } catch (Exception e) { return null; }
    }
}