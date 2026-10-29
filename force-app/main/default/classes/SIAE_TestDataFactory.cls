/**
 * @description Centralized factory for creating test data with sensible defaults.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */

@isTest
public class SIAE_TestDataFactory {

    // ─── Accounts ─────────────────────────────────────────────────────────

    public static List<Account> createAccounts(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                BillingCity = 'San Francisco',
                BillingState = 'CA',
                BillingCountry = 'USA',
                Industry = 'Technology',
                Type = 'Customer'
            ));
        }
        if (doInsert) insert accounts;
        return accounts;
    }

    public static Account createAccount(Boolean doInsert) {
        return createAccounts(1, doInsert)[0];
    }

    // ─── Opportunities ────────────────────────────────────────────────────

    public static List<Opportunity> createOpportunities(List<Account> accounts, Integer countPerAccount, Boolean doInsert) {
        List<Opportunity> opps = new List<Opportunity>();
        Integer idx = 0;
        for (Account acc : accounts) {
            for (Integer i = 0; i < countPerAccount; i++) {
                opps.add(new Opportunity(
                    Name = 'Test Opportunity ' + idx,
                    AccountId = acc.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Amount = 10000 + (idx * 1000)
                ));
                idx++;
            }
        }
        if (doInsert) insert opps;
        return opps;
    }

    // ─── Quotes ───────────────────────────────────────────────────────────

    public static List<Quote> createQuotes(List<Opportunity> opportunities, Integer countPerOpportunity, Boolean doInsert) {
        List<Quote> quotes = new List<Quote>();
        Integer idx = 0;
        for (Opportunity opp : opportunities) {
            for (Integer i = 0; i < countPerOpportunity; i++) {
                quotes.add(new Quote(
                    Name = 'Test Quote ' + idx,
                    OpportunityId = opp.Id,
                    Status = 'Draft',
                    Pricebook2Id = Test.getStandardPricebookId()
                ));
                idx++;
            }
        }
        if (doInsert) insert quotes;
        return quotes;
    }

    public static Quote createQuote(Opportunity opp, Boolean doInsert) {
        return createQuotes(new List<Opportunity>{ opp }, 1, doInsert)[0];
    }

    // ─── Products ─────────────────────────────────────────────────────────

    public static List<Product2> createProducts(Integer count, Boolean doInsert) {
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < count; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'PROD-' + i,
                IsActive = true,
                Family = 'Hardware'
            ));
        }
        if (doInsert) insert products;
        return products;
    }

    public static Product2 createProduct(Boolean doInsert) {
        return createProducts(1, doInsert)[0];
    }

    // ─── Pricebook Entries ────────────────────────────────────────────────

    public static List<PricebookEntry> createPricebookEntries(List<Product2> products, Id pricebookId, Boolean doInsert) {
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Integer i = 0; i < products.size(); i++) {
            entries.add(new PricebookEntry(
                Product2Id = products[i].Id,
                Pricebook2Id = pricebookId,
                UnitPrice = 100.00 + (i * 10),
                IsActive = true
            ));
        }
        if (doInsert) insert entries;
        return entries;
    }

    // ─── Quote Line Items ─────────────────────────────────────────────────

    public static List<QuoteLineItem> createQuoteLineItems(List<Quote> quotes, List<PricebookEntry> pricebookEntries, Boolean doInsert) {
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        Integer entryIdx = 0;
        for (Quote q : quotes) {
            PricebookEntry pbe = pricebookEntries[Math.mod(entryIdx, pricebookEntries.size())];
            qlis.add(new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbe.Id,
                Product2Id = pbe.Product2Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            ));
            entryIdx++;
        }
        if (doInsert) insert qlis;
        return qlis;
    }

    public static List<QuoteLineItem> createQuoteLineItems(Integer count, Quote quote, PricebookEntry pbe, Boolean doInsert) {
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < count; i++) {
            qlis.add(new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1 + i,
                UnitPrice = pbe.UnitPrice
            ));
        }
        if (doInsert) insert qlis;
        return qlis;
    }

    // ─── Orders ───────────────────────────────────────────────────────────

    public static List<Order> createOrders(List<Account> accounts, Integer countPerAccount, Boolean doInsert) {
        List<Order> orders = new List<Order>();
        Integer idx = 0;
        for (Account acc : accounts) {
            for (Integer i = 0; i < countPerAccount; i++) {
                orders.add(new Order(
                    AccountId = acc.Id,
                    EffectiveDate = Date.today(),
                    Status = 'Draft',
                    Pricebook2Id = Test.getStandardPricebookId()
                ));
                idx++;
            }
        }
        if (doInsert) insert orders;
        return orders;
    }

    public static Order createOrder(Account acc, Boolean doInsert) {
        return createOrders(new List<Account>{ acc }, 1, doInsert)[0];
    }

    // ─── Order Items ──────────────────────────────────────────────────────

    public static List<OrderItem> createOrderItems(Integer count, Order order, PricebookEntry pbe, Boolean doInsert) {
        List<OrderItem> orderItems = new List<OrderItem>();
        for (Integer i = 0; i < count; i++) {
            orderItems.add(new OrderItem(
                OrderId = order.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1 + i,
                UnitPrice = pbe.UnitPrice
            ));
        }
        if (doInsert) insert orderItems;
        return orderItems;
    }
}