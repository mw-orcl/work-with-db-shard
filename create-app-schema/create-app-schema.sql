set echo on 
set termout on
set time on
spool /home/oracle/create_app_schema.lst
REM
REM Connect to the Shard Catalog and Create Schema
REM
connect sys/your-own-sys-password@sdbsc0:1521/sdbpdb as sysdba
REM alter session set container=catapdb;
alter session enable shard ddl;
create user app_schema identified by App_Schema_Pass_123;
grant connect, resource, alter session to app_schema;
grant execute on dbms_crypto to app_schema;
grant create table, create procedure, create tablespace, create materialized view to app_schema;
grant unlimited tablespace to app_schema;
grant select_catalog_role to app_schema;
grant all privileges to app_schema;
grant gsmadmin_role to app_schema;
grant dba to app_schema;


REM
REM Create a tablespace set for SHARDED tables
REM
CREATE TABLESPACE SET  TSP_SET_1 using template (datafile size 100m autoextend on next 10M maxsize unlimited extent management  local segment space management auto );

REM
REM Create a tablespace for DUPLICATED tables
REM
CREATE TABLESPACE products_tsp datafile size 100m autoextend on next 10M maxsize unlimited extent management local uniform size 1m; 
 
REM
REM Create Sharded and Duplicated tables
REM
connect app_schema/App_Schema_Pass_123@sdbsc0:1521/sdbpdb
alter session enable shard ddl;
REM
REM Create a Sharded table for Customers  (Root table)
REM
CREATE SHARDED TABLE Customers
(
  CustId      VARCHAR2(60) NOT NULL,
  FirstName   VARCHAR2(60),
  LastName    VARCHAR2(60),
  Class       VARCHAR2(10),
  Geo         VARCHAR2(8),
  CustProfile VARCHAR2(4000),
  Passwd      RAW(60),
  CONSTRAINT pk_customers PRIMARY KEY (CustId),
  CONSTRAINT json_customers CHECK (CustProfile IS JSON)
) TABLESPACE SET TSP_SET_1
PARTITION BY CONSISTENT HASH (CustId) PARTITIONS AUTO;

REM
REM Create a Sharded table for Orders
REM
CREATE SHARDED TABLE Orders
(
  OrderId     INTEGER NOT NULL,
  CustId      VARCHAR2(60) NOT NULL,
  OrderDate   TIMESTAMP NOT NULL,
  SumTotal    NUMBER(19,4),
  Status      CHAR(4),
  constraint  pk_orders primary key (CustId, OrderId),
  constraint  fk_orders_parent foreign key (CustId) 
    references Customers on delete cascade
) partition by reference (fk_orders_parent);

REM
REM Create the sequence used for the OrderId column
REM
CREATE SEQUENCE Orders_Seq;

REM
REM Create a Sharded table for LineItems
REM
CREATE SHARDED TABLE LineItems
(
  OrderId     INTEGER NOT NULL,
  CustId      VARCHAR2(60) NOT NULL,
  ProductId   INTEGER NOT NULL,
  Price       NUMBER(19,4),
  Qty         NUMBER,
  constraint  pk_items primary key (CustId, OrderId, ProductId),
  constraint  fk_items_parent foreign key (CustId, OrderId)
    references Orders on delete cascade
) partition by reference (fk_items_parent);

REM
REM Create Duplicated table for Products
REM
CREATE DUPLICATED TABLE Products
(
  ProductId  INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  Name       VARCHAR2(128),
  DescrUri   VARCHAR2(128),
  LastPrice  NUMBER(19,4)
) TABLESPACE products_tsp;

REM
REM Create functions for Password creation and checking – used by the REM demo loader application
REM

CREATE OR REPLACE FUNCTION PasswCreate(PASSW IN RAW)
  RETURN RAW
IS
  Salt RAW(8);
BEGIN
  Salt := DBMS_CRYPTO.RANDOMBYTES(8);
  RETURN UTL_RAW.CONCAT(Salt, DBMS_CRYPTO.HASH(UTL_RAW.CONCAT(Salt, PASSW), DBMS_CRYPTO.HASH_SH256));
END;
/

CREATE OR REPLACE FUNCTION PasswCheck(PASSW IN RAW, PHASH IN RAW)
  RETURN INTEGER IS
BEGIN
  RETURN UTL_RAW.COMPARE(
      DBMS_CRYPTO.HASH(UTL_RAW.CONCAT(UTL_RAW.SUBSTR(PHASH, 1, 8), PASSW), DBMS_CRYPTO.HASH_SH256),
      UTL_RAW.SUBSTR(PHASH, 9));
END;
/

REM
REM
select table_name from user_tables;
REM
REM
spool off
