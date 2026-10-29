/**
 * @description Utility per creare e tenere allineati Contact tecnico e BillingAccount da Account.
 *              Il Contact serve solo come BillToContact.
 *              Gli indirizzi vengono copiati solo sul BillingAccount.
 */
public without sharing class SIAE_TR_Account_U_ManageBillingAccount {

    private static final String BILLING_ACCOUNT_OBJECT = 'BillingAccount';

    private static final String FIELD_NAME = 'Name';
    private static final String FIELD_ACCOUNT_ID = 'AccountId';
    private static final String FIELD_BILL_TO_CONTACT_ID = 'BillToContactId';
    private static final String FIELD_IS_DEFAULT_BILLING_PROFILE = 'IsDefaultBillingProfile';

    // Campi Account che, se modificati, richiedono aggiornamento del nome su Contact e BillingAccount
    private static final List<String> ACCOUNT_NAME_FIELDS = new List<String>{
        'Name'
    };

    // Campi Account che, se modificati, richiedono aggiornamento degli indirizzi sul BillingAccount
    private static final List<String> ACCOUNT_ADDRESS_FIELDS = new List<String>{
        'BillingStreet',
        'BillingCity',
        'BillingState',
        'BillingPostalCode',
        'BillingCountry',
        'BillingStateCode',
        'BillingCountryCode',
        'BillingLatitude',
        'BillingLongitude',
        'BillingGeocodeAccuracy',
        'ShippingStreet',
        'ShippingCity',
        'ShippingState',
        'ShippingPostalCode',
        'ShippingCountry',
        'ShippingStateCode',
        'ShippingCountryCode',
        'ShippingLatitude',
        'ShippingLongitude',
        'ShippingGeocodeAccuracy'
    };

    // Suffix dei campi indirizzo usati per comporre i nomi campo sorgente/destinazione
    private static final List<String> ADDRESS_SUFFIXES = new List<String>{
        'Street',
        'City',
        'State',
        'PostalCode',
        'Country',
        'StateCode',
        'CountryCode',
        'Latitude',
        'Longitude',
        'GeocodeAccuracy'
    };

    // Cache dei campi del BillingAccount, per evitare describe ripetuti
    private static Map<String, Schema.SObjectField> billingAccountFields;

    /**
     * @description Gestione after insert Account.
     *              Crea un Contact tecnico e un BillingAccount default per ogni Account.
     */
    public static void manageAfterInsert(Map<Id, Account> mapNew) {
        if (mapNew == null || mapNew.isEmpty()) return;
        if (!isBillingAccountAvailable()) return;

        List<Account> accounts = getEligibleAccounts(mapNew.values());

        if (accounts.isEmpty()) return;

        createContactsAndBillingAccounts(accounts);
    }

    /**
     * @description Gestione after update Account.
     *              Aggiorna Contact e BillingAccount solo se cambiano nome o indirizzi.
     */
    public static void manageAfterUpdate(Map<Id, Account> mapOld, Map<Id, Account> mapNew) {
        if (mapOld == null || mapNew == null || mapNew.isEmpty()) return;
        if (!isBillingAccountAvailable()) return;

        Map<Id, AccountSyncContext> contextsByAccountId = getAccountsToSync(mapOld, mapNew);

        if (contextsByAccountId.isEmpty()) return;

        syncContactsAndBillingAccounts(contextsByAccountId);
    }

    /**
     * @description Crea prima i Contact tecnici, poi crea i BillingAccount collegati.
     */
    private static void createContactsAndBillingAccounts(List<Account> accounts) {
        List<Contact> contactsToInsert = new List<Contact>();

        // Creo un Contact tecnico per ogni Account
        for (Account accountRecord : accounts) {
            contactsToInsert.add(new Contact(
                AccountId = accountRecord.Id,
                LastName = getContactLastName(accountRecord.Name)
            ));
        }

        if (!contactsToInsert.isEmpty()) insert contactsToInsert;

        Map<Id, Contact> contactByAccountId = new Map<Id, Contact>();

        // Mappa AccountId -> Contact creato
        for (Contact contactRecord : contactsToInsert)
            contactByAccountId.put(contactRecord.AccountId, contactRecord);

        List<SObject> billingAccountsToInsert = new List<SObject>();

        // Creo un BillingAccount default per ogni Account
        for (Account accountRecord : accounts) {
            Contact contactRecord = contactByAccountId.get(accountRecord.Id);

            SObject billingAccount = newBillingAccount();

            putBillingAccountValue(billingAccount, FIELD_NAME, getBillingAccountName(accountRecord.Name), true);
            putBillingAccountValue(billingAccount, FIELD_ACCOUNT_ID, accountRecord.Id, true);
            putBillingAccountValue(billingAccount, FIELD_BILL_TO_CONTACT_ID, contactRecord != null ? contactRecord.Id : null, true);
            putBillingAccountValue(billingAccount, FIELD_IS_DEFAULT_BILLING_PROFILE, true, true);

            // Copio Billing Address e Shipping Address dell'Account sul BillingAccount
            copyAccountAddressesOnBillingAccount(accountRecord, billingAccount, true);

            billingAccountsToInsert.add(billingAccount);
        }

        if (!billingAccountsToInsert.isEmpty()) insert billingAccountsToInsert;
    }

    /**
     * @description Sincronizza Contact e BillingAccount esistenti.
     *              Se mancano, li crea.
     */
    private static void syncContactsAndBillingAccounts(Map<Id, AccountSyncContext> contextsByAccountId) {
        Map<Id, SObject> billingAccountByAccountId = queryDefaultBillingAccountsByAccountIds(contextsByAccountId.keySet());

        List<Contact> contactsToInsert = new List<Contact>();
        List<Contact> contactsToUpdate = new List<Contact>();

        // Gestione Contact: creo se manca, aggiorno se cambia il nome Account
        for (Id accountId : contextsByAccountId.keySet()) {
            AccountSyncContext context = contextsByAccountId.get(accountId);
            SObject billingAccount = billingAccountByAccountId.get(accountId);
            Id billToContactId = getBillingAccountContactId(billingAccount);

            if (billingAccount == null || billToContactId == null) {
                contactsToInsert.add(new Contact(
                    AccountId = accountId,
                    LastName = getContactLastName(context.accountRecord.Name)
                ));

                continue;
            }

            if (context.nameChanged) {
                contactsToUpdate.add(new Contact(
                    Id = billToContactId,
                    LastName = getContactLastName(context.accountRecord.Name)
                ));
            }
        }

        if (!contactsToInsert.isEmpty()) insert contactsToInsert;
        if (!contactsToUpdate.isEmpty()) update contactsToUpdate;

        Map<Id, Contact> newContactByAccountId = new Map<Id, Contact>();

        // Mappa AccountId -> nuovo Contact creato
        for (Contact contactRecord : contactsToInsert)
            newContactByAccountId.put(contactRecord.AccountId, contactRecord);

        List<SObject> billingAccountsToInsert = new List<SObject>();
        List<SObject> billingAccountsToUpdate = new List<SObject>();

        // Gestione BillingAccount: creo se manca, aggiorno se esiste
        for (Id accountId : contextsByAccountId.keySet()) {
            AccountSyncContext context = contextsByAccountId.get(accountId);
            Account accountRecord = context.accountRecord;
            SObject existingBillingAccount = billingAccountByAccountId.get(accountId);
            Contact newContact = newContactByAccountId.get(accountId);

            // Se il BillingAccount non esiste, lo creo da zero
            if (existingBillingAccount == null) {
                SObject billingAccountToInsert = newBillingAccount();

                putBillingAccountValue(billingAccountToInsert, FIELD_NAME, getBillingAccountName(accountRecord.Name), true);
                putBillingAccountValue(billingAccountToInsert, FIELD_ACCOUNT_ID, accountRecord.Id, true);
                putBillingAccountValue(billingAccountToInsert, FIELD_BILL_TO_CONTACT_ID, newContact != null ? newContact.Id : null, true);
                putBillingAccountValue(billingAccountToInsert, FIELD_IS_DEFAULT_BILLING_PROFILE, true, true);

                copyAccountAddressesOnBillingAccount(accountRecord, billingAccountToInsert, true);

                billingAccountsToInsert.add(billingAccountToInsert);
                continue;
            }

            // Se il BillingAccount esiste, aggiorno solo i campi necessari
            SObject billingAccountToUpdate = newBillingAccount();
            billingAccountToUpdate.put('Id', existingBillingAccount.get('Id'));

            if (context.nameChanged)
                putBillingAccountValue(billingAccountToUpdate, FIELD_NAME, getBillingAccountName(accountRecord.Name), false);

            if (newContact != null)
                putBillingAccountValue(billingAccountToUpdate, FIELD_BILL_TO_CONTACT_ID, newContact.Id, false);

            if (context.addressChanged)
                copyAccountAddressesOnBillingAccount(accountRecord, billingAccountToUpdate, false);

            if (hasFieldsToUpdate(billingAccountToUpdate)) billingAccountsToUpdate.add(billingAccountToUpdate);
        }

        if (!billingAccountsToInsert.isEmpty()) insert billingAccountsToInsert;
        if (!billingAccountsToUpdate.isEmpty()) update billingAccountsToUpdate;
    }

    /**
     * @description Restituisce solo gli Account che hanno cambiato nome o indirizzo.
     */
    private static Map<Id, AccountSyncContext> getAccountsToSync(Map<Id, Account> mapOld, Map<Id, Account> mapNew) {
        Map<Id, AccountSyncContext> contextsByAccountId = new Map<Id, AccountSyncContext>();

        for (Id accountId : mapNew.keySet()) {
            Account oldAccount = mapOld.get(accountId);
            Account newAccount = mapNew.get(accountId);

            if (oldAccount == null || newAccount == null) continue;
            if (isPersonAccount(newAccount)) continue;

            Boolean nameChanged = hasChangedFields(oldAccount, newAccount, ACCOUNT_NAME_FIELDS);
            Boolean addressChanged = hasChangedFields(oldAccount, newAccount, ACCOUNT_ADDRESS_FIELDS);

            if (nameChanged || addressChanged)
                contextsByAccountId.put(accountId, new AccountSyncContext(newAccount, nameChanged, addressChanged));
        }

        return contextsByAccountId;
    }

    /**
     * @description Filtra gli Account da gestire.
     */
    private static List<Account> getEligibleAccounts(List<Account> accounts) {
        List<Account> eligibleAccounts = new List<Account>();

        for (Account accountRecord : accounts) {
            if (accountRecord == null) continue;
            if (isPersonAccount(accountRecord)) continue;

            eligibleAccounts.add(accountRecord);
        }

        return eligibleAccounts;
    }

    /**
     * @description Controlla se almeno uno dei campi indicati è cambiato.
     */
    private static Boolean hasChangedFields(Account oldAccount, Account newAccount, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            if (!accountHasField(fieldName)) continue;
            if (areDifferent(oldAccount.get(fieldName), newAccount.get(fieldName))) return true;
        }

        return false;
    }

    /**
     * @description Confronta due valori gestendo anche i null.
     */
    private static Boolean areDifferent(Object oldValue, Object newValue) {
        if (oldValue == null && newValue == null) return false;
        if (oldValue == null || newValue == null) return true;

        return String.valueOf(oldValue) != String.valueOf(newValue);
    }

    /**
     * @description Copia Billing Address e Shipping Address dell'Account sul BillingAccount.
     */
    private static void copyAccountAddressesOnBillingAccount(Account accountRecord, SObject billingAccount, Boolean isInsert) {
        copyAddress(
            accountRecord,
            billingAccount,
            'Billing',
            new List<String>{ 'PrimaryBillAddr', 'PrimaryBillingAddress', 'BillingAddress', 'Billing' },
            isInsert
        );

        copyAddress(
            accountRecord,
            billingAccount,
            'Shipping',
            new List<String>{ 'ShippingAddress', 'Shipping', 'ShippingAddr' },
            isInsert
        );
    }

    /**
     * @description Copia tutti i componenti di un indirizzo.
     */
    private static void copyAddress(
        Account accountRecord,
        SObject billingAccount,
        String accountAddressPrefix,
        List<String> billingAccountAddressPrefixes,
        Boolean isInsert
    ) {
        for (String suffix : ADDRESS_SUFFIXES) {
            String sourceField = accountAddressPrefix + suffix;

            if (!accountHasField(sourceField)) continue;

            Object value = accountRecord.get(sourceField);

            putFirstAvailableAddressValue(
                billingAccount,
                billingAccountAddressPrefixes,
                suffix,
                value,
                isInsert
            );
        }
    }

    /**
     * @description Scrive il valore sul primo campo indirizzo disponibile del BillingAccount.
     */
    private static void putFirstAvailableAddressValue(
        SObject billingAccount,
        List<String> addressPrefixes,
        String suffix,
        Object value,
        Boolean isInsert
    ) {
        for (String prefix : addressPrefixes) {
            String targetField = prefix + suffix;

            if (!isBillingAccountFieldWriteable(targetField, isInsert)) continue;

            billingAccount.put(targetField, value);
            return;
        }
    }

    /**
     * @description Recupera il BillingAccount default collegato agli Account.
     */
    private static Map<Id, SObject> queryDefaultBillingAccountsByAccountIds(Set<Id> accountIds) {
        Map<Id, SObject> billingAccountByAccountId = new Map<Id, SObject>();

        if (accountIds == null || accountIds.isEmpty()) return billingAccountByAccountId;
        if (!billingAccountHasField(FIELD_ACCOUNT_ID)) return billingAccountByAccountId;

        Map<String, Schema.SObjectField> fields = getBillingAccountFields();
        List<String> selectFields = new List<String>{ 'Id', FIELD_ACCOUNT_ID };

        if (fields.containsKey(FIELD_BILL_TO_CONTACT_ID)) selectFields.add(FIELD_BILL_TO_CONTACT_ID);
        if (fields.containsKey(FIELD_IS_DEFAULT_BILLING_PROFILE)) selectFields.add(FIELD_IS_DEFAULT_BILLING_PROFILE);

        String query =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + BILLING_ACCOUNT_OBJECT +
            ' WHERE ' + FIELD_ACCOUNT_ID + ' IN :accountIds';

        if (fields.containsKey(FIELD_IS_DEFAULT_BILLING_PROFILE))
            query += ' AND ' + FIELD_IS_DEFAULT_BILLING_PROFILE + ' = true';

        query += ' ORDER BY CreatedDate ASC';

        for (SObject billingAccount : Database.query(query)) {
            Id accountId = (Id) billingAccount.get(FIELD_ACCOUNT_ID);

            if (accountId == null) continue;
            if (!billingAccountByAccountId.containsKey(accountId))
                billingAccountByAccountId.put(accountId, billingAccount);
        }

        return billingAccountByAccountId;
    }

    /**
     * @description Recupera il Contact collegato al BillingAccount.
     */
    private static Id getBillingAccountContactId(SObject billingAccount) {
        if (billingAccount == null) return null;
        if (!billingAccountHasField(FIELD_BILL_TO_CONTACT_ID)) return null;

        return (Id) billingAccount.get(FIELD_BILL_TO_CONTACT_ID);
    }

    /**
     * @description Crea un nuovo SObject BillingAccount dinamico.
     */
    private static SObject newBillingAccount() {
        return Schema.getGlobalDescribe().get(BILLING_ACCOUNT_OBJECT).newSObject();
    }

    /**
     * @description Controlla se l'oggetto BillingAccount esiste nell'org.
     */
    private static Boolean isBillingAccountAvailable() {
        return Schema.getGlobalDescribe().containsKey(BILLING_ACCOUNT_OBJECT);
    }

    /**
     * @description Valorizza un campo del BillingAccount solo se esiste ed è scrivibile.
     */
    private static void putBillingAccountValue(SObject billingAccount, String fieldName, Object value, Boolean isInsert) {
        if (!isBillingAccountFieldWriteable(fieldName, isInsert)) return;

        billingAccount.put(fieldName, value);
    }

    /**
     * @description Controlla se un campo del BillingAccount è scrivibile in insert o update.
     */
    private static Boolean isBillingAccountFieldWriteable(String fieldName, Boolean isInsert) {
        if (!billingAccountHasField(fieldName)) return false;

        Schema.DescribeFieldResult describeResult = getBillingAccountFields().get(fieldName).getDescribe();

        return isInsert ? describeResult.isCreateable() : describeResult.isUpdateable();
    }

    /**
     * @description Controlla se il campo esiste sul BillingAccount.
     */
    private static Boolean billingAccountHasField(String fieldName) {
        return isBillingAccountAvailable()
            && getBillingAccountFields().containsKey(fieldName);
    }

    /**
     * @description Recupera i campi del BillingAccount e li salva in cache.
     */
    private static Map<String, Schema.SObjectField> getBillingAccountFields() {
        if (billingAccountFields == null) {
            billingAccountFields = Schema.getGlobalDescribe()
                .get(BILLING_ACCOUNT_OBJECT)
                .getDescribe()
                .fields
                .getMap();
        }

        return billingAccountFields;
    }

    /**
     * @description Controlla se il campo esiste su Account.
     */
    private static Boolean accountHasField(String fieldName) {
        return Account.SObjectType.getDescribe().fields.getMap().containsKey(fieldName);
    }

    /**
     * @description Esclude i Person Account dalla gestione.
     */
    private static Boolean isPersonAccount(Account accountRecord) {
        if (!accountHasField('IsPersonAccount')) return false;

        try {
            return accountRecord.get('IsPersonAccount') == true;
        } catch (Exception ex) {
            return false;
        }
    }

    /**
     * @description Controlla se un record ha campi da aggiornare oltre all'Id.
     */
    private static Boolean hasFieldsToUpdate(SObject recordToUpdate) {
        Map<String, Object> populatedFields = recordToUpdate.getPopulatedFieldsAsMap();

        return populatedFields != null && populatedFields.size() > 1;
    }

    /**
     * @description Restituisce il LastName del Contact tecnico.
     */
    private static String getContactLastName(String accountName) {
        String value = String.isBlank(accountName) ? 'Account' : accountName;

        return value.length() > 80 ? value.substring(0, 80) : value;
    }

    /**
     * @description Restituisce il Name del BillingAccount.
     */
    private static String getBillingAccountName(String accountName) {
        if (String.isBlank(accountName)) return 'Billing Account';

        Integer maxLength = getBillingAccountNameLength();

        if (maxLength != null && maxLength > 0 && accountName.length() > maxLength)
            return accountName.substring(0, maxLength);

        return accountName;
    }

    /**
     * @description Recupera la lunghezza massima del campo Name del BillingAccount.
     */
    private static Integer getBillingAccountNameLength() {
        if (!billingAccountHasField(FIELD_NAME)) return null;

        return getBillingAccountFields().get(FIELD_NAME).getDescribe().getLength();
    }

    /**
     * @description Wrapper interno con le informazioni di sincronizzazione dell'Account.
     */
    private class AccountSyncContext {
        public Account accountRecord;
        public Boolean nameChanged;
        public Boolean addressChanged;

        public AccountSyncContext(Account accountRecord, Boolean nameChanged, Boolean addressChanged) {
            this.accountRecord = accountRecord;
            this.nameChanged = nameChanged;
            this.addressChanged = addressChanged;
        }
    }
}