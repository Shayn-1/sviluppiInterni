@isTest
private class SIAE_UTIL_DML_T {

    @isTest
    static void testInsertRecord_single() {
        Account acc = new Account(Name = 'DML Insert Single');
        Test.startTest();
        SIAE_UTIL_DML.insertRecord(acc);
        Test.stopTest();
        System.assertNotEquals(null, acc.Id, 'Il record dovrebbe essere stato inserito');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'DML Insert Single']);
    }

    @isTest
    static void testInsertRecords_defaultOverload() {
        List<Account> accs = new List<Account>{ new Account(Name = 'DML Insert Test 1') };
        Test.startTest();
        SIAE_UTIL_DML.insertRecords(accs);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'DML Insert Test 1']);
        System.assertNotEquals(null, accs[0].Id);
    }

    @isTest
    static void testInsertRecords_withAllOrNone() {
        List<Account> accs = new List<Account>{ new Account(Name = 'DML Insert Test 2') };
        Test.startTest();
        SIAE_UTIL_DML.insertRecords(accs, true);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'DML Insert Test 2']);
    }

    @isTest
    static void testUpdateRecord_single() {
        Account acc = new Account(Name = 'DML Update Single Before');
        insert acc;
        acc.Name = 'DML Update Single After';
        Test.startTest();
        SIAE_UTIL_DML.updateRecord(acc);
        Test.stopTest();
        System.assertEquals('DML Update Single After', [SELECT Name FROM Account WHERE Id = :acc.Id].Name);
    }

    @isTest
    static void testUpdateRecords_defaultOverload() {
        Account acc = new Account(Name = 'DML Update Before');
        insert acc;
        acc.Name = 'DML Update After';
        Test.startTest();
        SIAE_UTIL_DML.updateRecords(new List<Account>{ acc });
        Test.stopTest();
        System.assertEquals('DML Update After', [SELECT Name FROM Account WHERE Id = :acc.Id].Name);
    }

    @isTest
    static void testUpdateRecords_withAllOrNone() {
        Account acc = new Account(Name = 'DML Update2 Before');
        insert acc;
        acc.Name = 'DML Update2 After';
        Test.startTest();
        SIAE_UTIL_DML.updateRecords(new List<Account>{ acc }, true);
        Test.stopTest();
        System.assertEquals('DML Update2 After', [SELECT Name FROM Account WHERE Id = :acc.Id].Name);
    }

    @isTest
    static void testInsertRecords_allOrNoneTrue_throwsAndLogs() {
        // Account senza Name (campo required) -> DmlException con allOrNone = true
        List<Account> accs = new List<Account>{ new Account() };
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            SIAE_UTIL_DML.insertRecords(accs, true);
        } catch (Exception ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Con allOrNone = true l\'eccezione deve essere rilanciata');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = null]);
    }

    @isTest
    static void testInsertRecords_allOrNoneFalse_partialSuccess() {
        // Un record valido + uno invalido (senza Name): con allOrNone = false
        // il valido viene salvato, l'invalido viene loggato senza lanciare eccezioni.
        List<Account> accs = new List<Account>{
            new Account(Name = 'DML Partial Valid'),
            new Account()
        };
        Test.startTest();
        SIAE_UTIL_DML.insertRecords(accs, false);
        Test.stopTest();
        System.assertNotEquals(null, accs[0].Id, 'Il record valido deve essere inserito');
        System.assertEquals(null, accs[1].Id, 'Il record invalido non deve essere inserito');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'DML Partial Valid']);
    }

    @isTest
    static void testUpdateRecords_allOrNoneFalse_partialSuccess() {
        Account valid = new Account(Name = 'DML Update Valid');
        Account toFail = new Account(Name = 'DML Update ToFail');
        insert new List<Account>{ valid, toFail };

        valid.Name = 'DML Update Valid Changed';
        toFail.Name = null; // campo required a null -> fallisce in update

        Test.startTest();
        SIAE_UTIL_DML.updateRecords(new List<Account>{ valid, toFail }, false);
        Test.stopTest();

        System.assertEquals('DML Update Valid Changed', [SELECT Name FROM Account WHERE Id = :valid.Id].Name);
        System.assertEquals('DML Update ToFail', [SELECT Name FROM Account WHERE Id = :toFail.Id].Name,
            'Il record fallito non deve essere modificato');
    }

    @isTest
    static void testUpdateRecords_allOrNoneTrue_throwsAndLogs() {
        Account acc = new Account(Name = 'DML Update Fail Before');
        insert acc;
        acc.Name = null; // campo required a null -> DmlException con allOrNone = true
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            SIAE_UTIL_DML.updateRecords(new List<Account>{ acc }, true);
        } catch (Exception ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Con allOrNone = true l\'eccezione deve essere rilanciata');
        System.assertEquals('DML Update Fail Before', [SELECT Name FROM Account WHERE Id = :acc.Id].Name,
            'L\'update fallito non deve modificare il record');
    }
}