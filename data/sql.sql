-- 1. ????? ???? ??????? (orders)
CREATE TABLE orders (
    od NUMBER PRIMARY KEY,                -- ???? ????? (??? ????)
    orderdate DATE,                       -- ????? ?????
    total NUMBER(10, 2),                  -- ???????? ?????
    discount NUMBER(10, 2),               -- ???? ?????
    tax NUMBER(10, 2),                    -- ???? ???????
    netprice NUMBER(10, 2),               -- ????? ?????? ??? ????? ????????
    salesd DATE,                          -- ????? ????? (???? ?? ???? Date)
    custd NUMBER                          -- ???? ?????? (???? ???)
);

-- 2. ????? ???? ?????? ????? (paydetails)
CREATE TABLE paydetails (
    pd NUMBER PRIMARY KEY,                -- ???? ????? (??? ????)
    paydate DATE,                         -- ????? ?????
    type VARCHAR2(50),                    -- ??? ????? (????? ?????? ?????...)
    amount NUMBER(10, 2),                 -- ?????? ???????
    ordered NUMBER,                       -- ??? ????? ??????? (???? Foreign Key)
    CONSTRAINT fk_paydetails_orders       -- ??? ??????? ??????? (??? ????????)
        FOREIGN KEY (ordered)
        REFERENCES orders(od)
);

-- ????? ??????? ?? ?? ?????? ?????
DELETE FROM paydetails;
DELETE FROM orders;

-- ????? ?????? ?? ???? orders
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (101, TO_DATE('2026-01-15', 'YYYY-MM-DD'), 1500.00, 100.00, 75.00, 1475.00, TO_DATE('2026-01-15', 'YYYY-MM-DD'), 1001);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (102, TO_DATE('2026-02-20', 'YYYY-MM-DD'), 2500.00, 250.00, 125.00, 2375.00, TO_DATE('2026-02-21', 'YYYY-MM-DD'), 1002);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (103, TO_DATE('2026-03-05', 'YYYY-MM-DD'), 800.00, 0.00, 40.00, 840.00, TO_DATE('2026-03-05', 'YYYY-MM-DD'), 1003);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (104, TO_DATE('2026-03-18', 'YYYY-MM-DD'), 3200.00, 300.00, 160.00, 3060.00, TO_DATE('2026-03-19', 'YYYY-MM-DD'), 1001);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (105, TO_DATE('2026-04-10', 'YYYY-MM-DD'), 450.00, 20.00, 22.50, 452.50, TO_DATE('2026-04-10', 'YYYY-MM-DD'), 1004);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (106, TO_DATE('2026-04-25', 'YYYY-MM-DD'), 5100.00, 500.00, 255.00, 4855.00, TO_DATE('2026-04-26', 'YYYY-MM-DD'), 1002);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (107, TO_DATE('2026-05-02', 'YYYY-MM-DD'), 1200.00, 80.00, 60.00, 1180.00, TO_DATE('2026-05-03', 'YYYY-MM-DD'), 1005);
INSERT INTO orders (od, orderdate, total, discount, tax, netprice, salesd, custd) VALUES (108, TO_DATE('2026-05-10', 'YYYY-MM-DD'), 670.00, 0.00, 33.50, 703.50, TO_DATE('2026-05-10', 'YYYY-MM-DD'), 1003);

-- ????? ?????? ?? ???? paydetails
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (201, TO_DATE('2026-01-15', 'YYYY-MM-DD'), 'Cash', 1475.00, 101);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (202, TO_DATE('2026-02-21', 'YYYY-MM-DD'), 'Credit Card', 2375.00, 102);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (203, TO_DATE('2026-03-05', 'YYYY-MM-DD'), 'Cash', 840.00, 103);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (204, TO_DATE('2026-03-20', 'YYYY-MM-DD'), 'Bank Transfer', 3060.00, 104);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (205, TO_DATE('2026-04-10', 'YYYY-MM-DD'), 'Cash', 452.50, 105);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (206, TO_DATE('2026-04-26', 'YYYY-MM-DD'), 'Credit Card', 2000.00, 106);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (207, TO_DATE('2026-04-27', 'YYYY-MM-DD'), 'Credit Card', 2855.00, 106);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (208, TO_DATE('2026-05-03', 'YYYY-MM-DD'), 'Cash', 1180.00, 107);
INSERT INTO paydetails (pd, paydate, type, amount, ordered) VALUES (209, TO_DATE('2026-05-10', 'YYYY-MM-DD'), 'Bank Transfer', 703.50, 108);

-- ????? ????? ????????
COMMIT;

