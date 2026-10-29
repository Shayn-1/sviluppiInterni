@isTest
private class SIAE_UTIL_SObject_T {

    @testSetup
    static void setupData() {
        insert new List<Account>{
            new Account(Name = 'SObject Test 1', BillingCity = 'Rome'),
            new Account(Name = 'SObject Test 2')
        };
    }

    @isTest
    static void testGetSetFieldValues_returnsValues() {
        List<Account> accounts = [SELECT Name FROM Account ORDER BY Name];
        Set<String> names = SIAE_UTIL_SObject.getSetFieldValues(accounts, 'Name');
        System.assertEquals(2, names.size());
        System.assert(names.contains('SObject Test 1'));
        System.assert(names.contains('SObject Test 2'));
    }

    @isTest
    static void testGetSetFieldValues_nullFieldExcluded() {
        List<Account> accounts = [SELECT Id, BillingCity FROM Account];
        Set<String> cities = SIAE_UTIL_SObject.getSetFieldValues(accounts, 'BillingCity');
        // Only Test 1 has BillingCity, Test 2 doesn't
        System.assertEquals(1, cities.size());
        System.assert(cities.contains('Rome'));
    }

    @isTest
    static void testCompareSObjects_noChanges() {
        Account acc = new Account(Name = 'Same');
        Map<String, String> diffs = SIAE_UTIL_SObject.compareSObjects(acc, acc);
        System.assertEquals(0, diffs.size());
    }

    @isTest
    static void testCompareSObjects_valueChanged() {
        Account prior = new Account(Name = 'Before');
        Account actual = new Account(Name = 'After');
        Map<String, String> diffs = SIAE_UTIL_SObject.compareSObjects(prior, actual);
        System.assert(diffs.containsKey('Name'));
        System.assert(diffs.get('Name').contains('Before'));
        System.assert(diffs.get('Name').contains('After'));
    }

    @isTest
    static void testCompareSObjects_fieldOnlyInPrior() {
        Account prior = new Account(Name = 'Test', BillingCity = 'Rome');
        Account actual = new Account(Name = 'Test');
        Map<String, String> diffs = SIAE_UTIL_SObject.compareSObjects(prior, actual);
        System.assert(diffs.containsKey('BillingCity'));
        System.assert(diffs.get('BillingCity').contains('Present in Prior'));
    }

    @isTest
    static void testCompareSObjects_fieldOnlyInActual() {
        Account prior = new Account(Name = 'Test');
        Account actual = new Account(Name = 'Test', BillingCity = 'Milan');
        Map<String, String> diffs = SIAE_UTIL_SObject.compareSObjects(prior, actual);
        System.assert(diffs.containsKey('BillingCity'));
        System.assert(diffs.get('BillingCity').contains('Missing in Prior'));
    }

    @isTest
    static void testGetListChanged_recordChanged() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'SObject Test 1' LIMIT 1];
        Map<Id, SObject> mapOld = new Map<Id, SObject>{ acc.Id => acc };
        Account accNew = acc.clone(true, true);
        accNew.Name = 'Changed';
        Map<Id, SObject> mapNew = new Map<Id, SObject>{ acc.Id => accNew };
        List<SObject> changed = SIAE_UTIL_SObject.getListChanged(new List<String>{ 'Name' }, mapOld, mapNew);
        System.assertEquals(1, changed.size());
    }

    @isTest
    static void testGetListChanged_noChange() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'SObject Test 1' LIMIT 1];
        Map<Id, SObject> mapOld = new Map<Id, SObject>{ acc.Id => acc };
        Map<Id, SObject> mapNew = new Map<Id, SObject>{ acc.Id => acc };
        List<SObject> changed = SIAE_UTIL_SObject.getListChanged(new List<String>{ 'Name' }, mapOld, mapNew);
        System.assertEquals(0, changed.size());
    }

    @isTest
    static void testGetListChangedIds_recordChanged() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'SObject Test 1' LIMIT 1];
        Map<Id, SObject> mapOld = new Map<Id, SObject>{ acc.Id => acc };
        Account accNew = acc.clone(true, true);
        accNew.Name = 'Changed';
        Map<Id, SObject> mapNew = new Map<Id, SObject>{ acc.Id => accNew };
        List<Id> changedIds = SIAE_UTIL_SObject.getListChangedIds(new List<String>{ 'Name' }, mapOld, mapNew);
        System.assertEquals(1, changedIds.size());
        System.assertEquals(acc.Id, changedIds[0]);
    }

    @isTest
    static void testGetListChangedIds_noChange() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'SObject Test 1' LIMIT 1];
        Map<Id, SObject> mapOld = new Map<Id, SObject>{ acc.Id => acc };
        Map<Id, SObject> mapNew = new Map<Id, SObject>{ acc.Id => acc };
        List<Id> changedIds = SIAE_UTIL_SObject.getListChangedIds(new List<String>{ 'Name' }, mapOld, mapNew);
        System.assertEquals(0, changedIds.size());
    }

    @isTest
    static void testCheckBlankField_nullRecord() {
        String result = SIAE_UTIL_SObject.checkBlankField(null, new List<String>{ 'Name' }, 'initial');
        System.assertEquals('initial', result);
    }

    @isTest
    static void testCheckBlankField_emptyFieldList() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        String result = SIAE_UTIL_SObject.checkBlankField(acc, new List<String>(), 'initial');
        System.assertEquals('initial', result);
    }

    @isTest
    static void testCheckBlankField_blankField() {
        Account acc = [SELECT Id, Name, BillingCity FROM Account WHERE Name = 'SObject Test 2' LIMIT 1];
        String result = SIAE_UTIL_SObject.checkBlankField(acc, new List<String>{ 'BillingCity' }, '');
        System.assert(result.length() > 0, 'Should report blank BillingCity');
    }

    @isTest
    static void testCheckBlankField_populatedField() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'SObject Test 1' LIMIT 1];
        String result = SIAE_UTIL_SObject.checkBlankField(acc, new List<String>{ 'Name' }, '');
        System.assertEquals('', result, 'No error for populated Name');
    }
}