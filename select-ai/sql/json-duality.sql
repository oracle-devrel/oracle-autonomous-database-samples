-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/* Apply AI SQL function to your data to summarize information, make recommendations and more */

/* PREREQUISITES
    Install the sample schema using script
        @data-create-sample-schema.sql
*/

/* Working with JSON in Autonomous Database
We can query relational data as JSON and also create JSON Collection tables. Different ways to work with JSON, 
flexiblity to work with JSON, and leverage relational tables by using JSON Duality views providing the best of both worlds. 
Let's look at a couple of ways of creating JSON collection tables, JSON Duality Views and querying JSON data.  
*/

-- JSON Collection 
drop table if exists movie_budget;
create json collection table movie_budget;

insert into movie_budget 
values (
    '{"movie_id": 1,"movie_title":"Avatar","movie_year": 2009, 
    "sku":"LYG56160","runtime": 162,"cast":["Sam Worthington","Zoe Saldana"],
    "studio":["20th Century Studios","Lightstorm Entertainment"]}' 
);
insert into movie_budget 
values (
    '{"movie_id": 2,"movie_title":"Ghostbusters II","movie_year": 1989, 
    "sku":"FWT19789","runtime": 104,"cast":["Bill Murray","Sigourney Weaver"],
    "genre":["Fantasy","Sci-Fi","Thriller","Comedy"]}' 
);

commit;

--see the JSON collection that has been created along with the ability to query it
select * 
from movie_budget;

--see attribute values using dot notation
select m.data.movie_title 
from movie_budget m;

--Let's add budget information to the movies
update movie_budget 
set data = JSON_TRANSFORM ( 
                data, 
                set '$.budgetUnit' = 'Million USD', 
                set '$.budget'=1000000);
commit;

-- query using json_value function this time
select 
    json_value(data, '$.movie_id') movie_id,
    json_value(data,'$.budget') budget 
from movie_budget;

--Change the budget for one of the movies
update movie_budget 
set data= JSON_TRANSFORM(
            data,  
            set '$.budget'=(json_value(data,'$.budget') * 2))
where JSON_VALUE(data,'$.movie_id')=2;

commit;

select 
    json_value(data, '$.movie_id') movie_id,
    json_value(data,'$.budget') budget 
from movie_budget;

--JSON Duality
/* We can work with our relational tables as JSON Documents by creating a JSON Duality View. 
Inserts, updates and deletes can be performed directly against the JSON Duality View and the changes happen on the underlying relational tables. 
This means that the JSON documents for these views will be updated without having to maintain each document, and the data is stored relationally 
avoiding duplication. 
*/
--Simple JSON view on one table

--We need primary keys on the tables that are part of the views
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW customer_dv AS
customer @insert @update @delete
{
    _id             : cust_id,
    FirstName       : first_name,
    LastName        : last_name,
    age             : age,
    Email           : email,
    street_address  : street_address,
    city            : city,
    postal_code     : postal_code
    yrs_customer    : yrs_customer
    pet             : pet
}
;

select * from customer_dv;

--JSON Duality View on a couple of tables. We do need primary keys on the tables being used in the views
alter table streams add constraint pk_streams primary key(cust_id,day_id, movie_id);

--JSON of the customers with the movies that they streamed
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW customer_streams_dv AS
customer @insert @update @delete
{
    _id             : cust_id,
    FirstName       : first_name,
    LastName        : last_name,
    age             : age,
    yrs_customer    : yrs_customer
    streams : streams @insert @update @delete
    [{        
        day_id : day_id
        genre_id : genre_id
        movie_id : movie_id
    }]
}
;

select * 
from customer_streams_dv;

-- Query the duality view using JSON functions. Pull back the customers who have been around for 10 years
select * 
from customer_streams_dv
where JSON_VALUE(data,'$.yrs_customer') > 10;


/* Now to insert a new record into customers and streams we can do that through the Duality View. 
Here we select first from customer and from streams to show there is no value */
select * from customer where cust_id=555;
select * from streams where cust_id=555;

--Now do an insert to the DV to add a new customer and add a stream
insert into customer_streams_dv values ('{
    "_id"            : 555,
    "FirstName"      : "Michelle",
    "LastName"       : "Jones",
    "age"            : 36,
    "yrs_customer"    : 0 ,
    "streams" : [{
                "day_id" : "2024-11-18T00:00:00",
                "genre_id" : 19,
                "movie_id" : 3694}]}');

commit;

--now we have rows in both of the underlying relational tables

select * from customer where cust_id=555;
select * from streams where cust_id=555;

/* With the JSON Collections and JSON Duality Views you can use API calls with GET and PUT to work
with the JSON in the database. We have just shown here SQL access to the JSON. */

