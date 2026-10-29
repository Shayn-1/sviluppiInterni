@IsTest
private class SIAE_CalcoloAccordoCommerciale_T {

    private static SIAE_AccordoCommerciale__c createAccordo(
        String name,
        String codiceAccordo,
        String codiceIncrocio,
        Decimal riduzioneCompensoBase,
        String voceQuota,
        Decimal percentualeQuotaSuNettoDDA,
        Decimal quotaUnitaria,
        Decimal minimoQuota,
        Decimal percentualeScontoDC
    ) {
        SIAE_AccordoCommerciale__c acc = new SIAE_AccordoCommerciale__c();
        acc.Name = name;
        acc.SIAE_CodiceAccordoCommerciale__c = codiceAccordo;
        acc.SIAE_CodiceDiIncrocio__c = codiceIncrocio;
        acc.SIAE_RiduzioneCompensoBase__c = riduzioneCompensoBase;
        acc.SIAE_VoceQuota__c = voceQuota;
        acc.SIAE_PercentualeQuotaSuNettoDDA__c = percentualeQuotaSuNettoDDA;
        acc.SIAE_QuotaUnitaria__c = quotaUnitaria;
        acc.SIAE_MinimoQuota__c = minimoQuota;
        acc.SIAE_PercentualeScontoDC__c = percentualeScontoDC;
        insert acc;
        return acc;
    }

    @IsTest
    static void testQuotaUnitaria() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 1',
            'CONFCO',
            'AS',
            0.10,
            'QUOTA_ASSOCIATIVA',
            null,
            5,
            null,
            0.20
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'CONFCO',
                'AS',
                4,
                100
            );
        Test.stopTest();

        
    }

    @IsTest
    static void testQuotaSuNettoDdaSenzaMinimo() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 2',
            'AICS',
            'AV',
            0.20,
            'QUOTA_ASSOCIATIVA',
            0.15,
            null,
            null,
            0.05
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'AICS',
                'AV',
                3,
                200
            );
        Test.stopTest();

        
    }

    @IsTest
    static void testQuotaSuNettoDdaConMinimo_MaggioreMinimo() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 3',
            'ANCI',
            'EC',
            0.10,
            'QUOTA_ASSOCIATIVA',
            0.10,
            null,
            15,
            0.08
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'ANCI',
                'EC',
                2,
                100
            );
        Test.stopTest();

        
    }

    @IsTest
    static void testQuotaSuNettoDdaConMinimo_MaggioreQuotaNetto() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 4',
            'ARCI',
            'FA',
            0.10,
            'QUOTA_ASSOCIATIVA',
            0.50,
            null,
            10,
            0.12
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'ARCI',
                'FA',
                2,
                100
            );
        Test.stopTest();

    }

    @IsTest
    static void testNessunaVoceQuota() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 5',
            'ASI',
            'LP',
            0.25,
            null,
            null,
            null,
            null,
            null
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'ASI',
                'LP',
                5,
                200
            );
        Test.stopTest();

    }

    @IsTest
    static void testVoceQuotaPresenteMaNessunValoreAssociato() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 6',
            'CSI',
            'SB',
            0.05,
            'QUOTA_ASSOCIATIVA',
            null,
            null,
            null,
            null
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'CSI',
                'SB',
                1,
                100
            );
        Test.stopTest();

    }

    @IsTest
    static void testRiduzioneNull() {
        SIAE_AccordoCommerciale__c acc = createAccordo(
            'Accordo Test 7',
            'UISP',
            'HO',
            null,
            'QUOTA_ASSOCIATIVA',
            null,
            12,
            null,
            0.30
        );

        Test.startTest();
        SIAE_CalcoloAccordoCommerciale.CalculationResult result =
            SIAE_CalcoloAccordoCommerciale.calculateAccordoCommerciale(
                'UISP',
                'HO',
                2,
                250
            );
        Test.stopTest();

    }


    
}