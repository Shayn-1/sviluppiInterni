@IsTest
private class SIAE_TR_Account_T {

    private static final String BILLING_ACCOUNT_OBJECT = 'BillingAccount';

    private static final String FIELD_NAME = 'Name';
    private static final String FIELD_ACCOUNT_ID = 'AccountId';
    private static final String FIELD_BILL_TO_CONTACT_ID = 'BillToContactId';
    private static final String FIELD_IS_DEFAULT_BILLING_PROFILE = 'IsDefaultBillingProfile';

    @IsTest
    static void shouldCreateContactAndBillingAccountAfterInsert() {
        resetFlags();

        Test.startTest();
        Account acc = createAccount('Account Test Insert');
        Test.stopTest();

        Contact contactRecord = getContactByAccountId(acc.Id);
        System.assertNotEquals(null, contactRecord, 'Dopo insert Account deve essere creato un Contact tecnico.');
        System.assertEquals(acc.Id, contactRecord.AccountId, 'Il Contact deve essere collegato all’Account.');
        System.assertEquals(acc.Name, contactRecord.LastName, 'Il LastName del Contact deve essere uguale al nome Account.');

        SObject billingAccount = getBillingAccountByAccountId(acc.Id);
        System.assertNotEquals(null, billingAccount, 'Dopo insert Account deve essere creato un BillingAccount.');

        assertBillingAccountBaseFields(billingAccount, acc, contactRecord.Id);
        assertBillingAccountAddressFields(billingAccount, acc);
    }

    @IsTest
    static void shouldUpdateContactAndBillingAccountNameAfterAccountNameChange() {
        resetFlags();

        Account acc = createAccount('Account Test Name Before');

        Contact oldContact = getContactByAccountId(acc.Id);
        System.assertNotEquals(null, oldContact, 'Il Contact tecnico deve essere presente prima dell’update.');

        Test.startTest();
        acc.Name = 'Account Test Name After';
        update acc;
        Test.stopTest();

        Contact updatedContact = [
            SELECT Id, AccountId, LastName
            FROM Contact
            WHERE Id = :oldContact.Id
        ];

        SObject billingAccount = getBillingAccountByAccountId(acc.Id);

        System.assertEquals(
            'Account Test Name After',
            updatedContact.LastName,
            'Se cambia il nome Account, deve aggiornarsi il LastName del Contact.'
        );

        if (billingAccountHasField(FIELD_NAME)) {
            System.assertEquals(
                'Account Test Name After',
                String.valueOf(billingAccount.get(FIELD_NAME)),
                'Se cambia il nome Account, deve aggiornarsi il Name del BillingAccount.'
            );
        }
    }

    @IsTest
    static void shouldUpdateBillingAccountAddressAfterAccountAddressChange() {
        resetFlags();

        Account acc = createAccount('Account Test Address Before');

        Test.startTest();
        acc.BillingStreet = 'Via Billing Aggiornata 10';
        acc.BillingCity = 'Roma Aggiornata';
        acc.BillingPostalCode = '00199';

        acc.ShippingStreet = 'Via Shipping Aggiornata 20';
        acc.ShippingCity = 'Milano Aggiornata';
        acc.ShippingPostalCode = '20199';

        update acc;
        Test.stopTest();

        SObject billingAccount = getBillingAccountByAccountId(acc.Id);
        System.assertNotEquals(null, billingAccount, 'Il BillingAccount deve esistere dopo update indirizzi.');

        assertBillingAccountAddressFields(billingAccount, acc);
    }

    @IsTest
    static void shouldCreateMissingContactAndBillingAccountOnUpdate() {
        resetFlags();

        SIAE_TR_Account_Handler.triggerOff = true;

        Account acc = createAccount('Account Test Missing Records');

        System.assertEquals(
            null,
            getBillingAccountByAccountId(acc.Id),
            'Con triggerOff attivo, il BillingAccount non deve essere creato in insert.'
        );

        SIAE_TR_Account_Handler.triggerOff = false;

        Test.startTest();
        acc.Name = 'Account Test Missing Records Updated';
        update acc;
        Test.stopTest();

        Contact contactRecord = getContactByAccountId(acc.Id);
        SObject billingAccount = getBillingAccountByAccountId(acc.Id);

        System.assertNotEquals(null, contactRecord, 'Se mancano i record collegati, l’update deve creare il Contact.');
        System.assertNotEquals(null, billingAccount, 'Se manca il BillingAccount, l’update deve crearlo.');

        assertBillingAccountBaseFields(billingAccount, acc, contactRecord.Id);
    }

    @IsTest
    static void shouldDoNothingWhenNoRelevantFieldsChange() {
        resetFlags();

        Account acc = createAccount('Account Test No Relevant Change');

        Contact contactBefore = getContactByAccountId(acc.Id);
        SObject billingAccountBefore = getBillingAccountByAccountId(acc.Id);

        System.assertNotEquals(null, contactBefore, 'Il Contact deve essere presente prima dell’update non rilevante.');
        System.assertNotEquals(null, billingAccountBefore, 'Il BillingAccount deve essere presente prima dell’update non rilevante.');

        Test.startTest();
        acc.Phone = '0612345678';
        update acc;
        Test.stopTest();

        Contact contactAfter = getContactByAccountId(acc.Id);
        SObject billingAccountAfter = getBillingAccountByAccountId(acc.Id);

        System.assertEquals(
            contactBefore.Id,
            contactAfter.Id,
            'Un update non rilevante non deve creare un nuovo Contact.'
        );

        System.assertEquals(
            billingAccountBefore.get('Id'),
            billingAccountAfter.get('Id'),
            'Un update non rilevante non deve creare un nuovo BillingAccount.'
        );
    }

    @IsTest
    static void shouldSkipTriggerWhenTriggerOffIsTrue() {
        resetFlags();

        try {
            SIAE_TR_Account_Handler.triggerOff = true;

            Test.startTest();
            Account acc = createAccount('Account Test Trigger Off');
            Test.stopTest();

            System.assertEquals(
                null,
                getContactByAccountId(acc.Id),
                'Con triggerOff attivo, il Contact tecnico non deve essere creato.'
            );

            System.assertEquals(
                null,
                getBillingAccountByAccountId(acc.Id),
                'Con triggerOff attivo, il BillingAccount non deve essere creato.'
            );

        } finally {
            SIAE_TR_Account_Handler.triggerOff = false;
        }
    }

    @IsTest
    static void shouldCoverHandlerEmptyMethodsAndFlags() {
        resetFlags();
    
        SIAE_TR_Account_Handler handler = new SIAE_TR_Account_Handler();
    
        System.assertEquals(false, handler.skipTrigger(), 'Di default il trigger non deve essere skippato.');
        System.assertEquals(false, handler.stopRecursion(), 'Di default non deve bloccare la ricorsione.');
    
        handler.executedTrigger();
        handler.onBeforeInsert(new List<SObject>());
        handler.onBeforeUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        handler.onBeforeDelete(new Map<Id, SObject>());
        handler.onAfterInsert(new Map<Id, SObject>());
        handler.onAfterUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        handler.onAfterDelete(new Map<Id, SObject>());
        handler.onAfterUndelete(new Map<Id, SObject>());
    }

    private static void resetFlags() {
        SIAE_TR_Account_Handler.triggerOff = false;
    }

    private static Account createAccount(String name) {
        Account acc = new Account(
            Name = name,
            BillingStreet = 'Via Billing 1',
            BillingCity = 'Roma',
            BillingPostalCode = '00100',
            ShippingStreet = 'Via Shipping 1',
            ShippingCity = 'Milano',
            ShippingPostalCode = '20100'
        );

        insert acc;
        return acc;
    }

    private static Contact getContactByAccountId(Id accountId) {
        List<Contact> contacts = [
            SELECT Id, AccountId, LastName
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        return contacts.isEmpty() ? null : contacts[0];
    }

    private static SObject getBillingAccountByAccountId(Id accountId) {
        List<SObject> billingAccounts = getBillingAccountsByAccountId(accountId);

        return billingAccounts.isEmpty() ? null : billingAccounts[0];
    }

    private static List<SObject> getBillingAccountsByAccountId(Id accountId) {
        if (!isBillingAccountAvailable()) return new List<SObject>();

        String query =
            'SELECT ' + String.join(getBillingAccountSelectFields(), ', ') +
            ' FROM ' + BILLING_ACCOUNT_OBJECT +
            ' WHERE ' + FIELD_ACCOUNT_ID + ' = :accountId' +
            ' ORDER BY CreatedDate ASC';

        return Database.query(query);
    }

    private static List<String> getBillingAccountSelectFields() {
        Set<String> selectFields = new Set<String>{ 'Id' };

        addFieldIfExists(selectFields, FIELD_NAME);
        addFieldIfExists(selectFields, FIELD_ACCOUNT_ID);
        addFieldIfExists(selectFields, FIELD_BILL_TO_CONTACT_ID);
        addFieldIfExists(selectFields, FIELD_IS_DEFAULT_BILLING_PROFILE);

        addFieldIfExists(selectFields, getBillingAddressField('Street'));
        addFieldIfExists(selectFields, getBillingAddressField('City'));
        addFieldIfExists(selectFields, getBillingAddressField('PostalCode'));

        addFieldIfExists(selectFields, getShippingAddressField('Street'));
        addFieldIfExists(selectFields, getShippingAddressField('City'));
        addFieldIfExists(selectFields, getShippingAddressField('PostalCode'));

        return new List<String>(selectFields);
    }

    private static void assertBillingAccountBaseFields(SObject billingAccount, Account acc, Id expectedContactId) {
        if (billingAccountHasField(FIELD_NAME)) {
            System.assertEquals(
                acc.Name,
                String.valueOf(billingAccount.get(FIELD_NAME)),
                'Il BillingAccount deve avere lo stesso nome dell’Account.'
            );
        }

        if (billingAccountHasField(FIELD_ACCOUNT_ID)) {
            System.assertEquals(
                acc.Id,
                (Id) billingAccount.get(FIELD_ACCOUNT_ID),
                'Il BillingAccount deve essere collegato all’Account.'
            );
        }

        if (billingAccountHasField(FIELD_BILL_TO_CONTACT_ID)) {
            System.assertEquals(
                expectedContactId,
                (Id) billingAccount.get(FIELD_BILL_TO_CONTACT_ID),
                'Il BillingAccount deve essere collegato al Contact tecnico.'
            );
        }

        if (billingAccountHasField(FIELD_IS_DEFAULT_BILLING_PROFILE)) {
            System.assertEquals(
                true,
                (Boolean) billingAccount.get(FIELD_IS_DEFAULT_BILLING_PROFILE),
                'Il BillingAccount deve essere default billing profile.'
            );
        }
    }

    private static void assertBillingAccountAddressFields(SObject billingAccount, Account acc) {
        assertBillingAccountFieldValue(
            billingAccount,
            getBillingAddressField('Street'),
            acc.BillingStreet,
            'Il BillingAccount deve ricevere BillingStreet dall’Account.'
        );

        assertBillingAccountFieldValue(
            billingAccount,
            getBillingAddressField('City'),
            acc.BillingCity,
            'Il BillingAccount deve ricevere BillingCity dall’Account.'
        );

        assertBillingAccountFieldValue(
            billingAccount,
            getBillingAddressField('PostalCode'),
            acc.BillingPostalCode,
            'Il BillingAccount deve ricevere BillingPostalCode dall’Account.'
        );

        assertBillingAccountFieldValue(
            billingAccount,
            getShippingAddressField('Street'),
            acc.ShippingStreet,
            'Il BillingAccount deve ricevere ShippingStreet dall’Account.'
        );

        assertBillingAccountFieldValue(
            billingAccount,
            getShippingAddressField('City'),
            acc.ShippingCity,
            'Il BillingAccount deve ricevere ShippingCity dall’Account.'
        );

        assertBillingAccountFieldValue(
            billingAccount,
            getShippingAddressField('PostalCode'),
            acc.ShippingPostalCode,
            'Il BillingAccount deve ricevere ShippingPostalCode dall’Account.'
        );
    }

    private static void assertBillingAccountFieldValue(
        SObject billingAccount,
        String fieldName,
        Object expectedValue,
        String message
    ) {
        if (String.isBlank(fieldName)) return;
        if (!billingAccountHasField(fieldName)) return;

        System.assertEquals(
            String.valueOf(expectedValue),
            String.valueOf(billingAccount.get(fieldName)),
            message
        );
    }

    private static String getBillingAddressField(String suffix) {
        return getFirstExistingBillingAccountField(
            new List<String>{ 'PrimaryBillAddr', 'PrimaryBillingAddress', 'BillingAddress', 'Billing' },
            suffix
        );
    }

    private static String getShippingAddressField(String suffix) {
        return getFirstExistingBillingAccountField(
            new List<String>{ 'ShippingAddress', 'Shipping', 'ShippingAddr' },
            suffix
        );
    }

    private static String getFirstExistingBillingAccountField(List<String> prefixes, String suffix) {
        for (String prefix : prefixes) {
            String fieldName = prefix + suffix;

            if (billingAccountHasField(fieldName)) return fieldName;
        }

        return null;
    }

    private static void addFieldIfExists(Set<String> fields, String fieldName) {
        if (String.isBlank(fieldName)) return;
        if (!billingAccountHasField(fieldName)) return;

        fields.add(fieldName);
    }

    private static Boolean isBillingAccountAvailable() {
        return Schema.getGlobalDescribe().containsKey(BILLING_ACCOUNT_OBJECT);
    }

    private static Boolean billingAccountHasField(String fieldName) {
        if (String.isBlank(fieldName)) return false;
        if (!isBillingAccountAvailable()) return false;

        return Schema.getGlobalDescribe()
            .get(BILLING_ACCOUNT_OBJECT)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldName);
    }
}