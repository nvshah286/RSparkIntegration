library(dplyr)
library(nycflights13)
library(ggplot2)
library(sparklyr)
library(microbenchmark)
library(dbplyr)


sc <- spark_connect(master="local")

## RDD 
## DAG
## transformations & actions 

#  Reference Source (most of the code will be found here.)
# http://spark.rstudio.com/dplyr/

flights2 = nycflights13::flights


## sc is the spark context... a connection object to communicate between R & Spark cluster
str(sc)
class(sc)

##copying the data to spark instance from R .. not loading data from R memory
flights <- copy_to(sc, flights, "flights")
airlines <- copy_to(sc, airlines, "airlines")

## reading a csv file into spark
loandata <- spark_read_csv(sc, name = 'LoanData',
                           path = "/Users/nvs/Downloads/Data sets/bank-full.csv")

## This will show the class and structrue of the spark data frame. its stored on local spark cluster
class(flights)
str(flights)


## loads the environment variables in spark.
src_tbls(sc)

## Note : dplyr functions can directly be used on spark data frames and tables. 

select(flights,  year, month,dep_delay)

flights %>% 
  group_by(month) %>%
  summarize(avgDelay = mean(dep_delay, na.rm =T)) %>% 
  arrange(month)

## checking performance of loadin data from spark vs R memory 
## even for a simple filter function, you can compare the performance again.(spark is 6 times faster on average.)
microbenchmark(flights %>% filter(dep_delay > 1000))
microbenchmark(flights2 %>% filter(dep_delay > 1000))

## look for more complex functions. 
arrange(flights, desc(dep_delay))
summarise(flights, mean_dep_delay = mean(dep_delay))

## All these are instances are not loaded into R. 
##these are lazy instances and evaluated at runtime only.

## When we look into Spark console, we can see th DAG for these processes.
## These are Spark "transformations" stored as spark_tbl instances on R memory.
## They run when they are called everytime. Unless we capture the output using collect function
## In that case, it will be dumped as data frame in R memory.

c1 <- filter(flights, day == 17, month == 5, carrier %in% c('UA', 'WN', 'AA', 'DL'))
c2 <- select(c1, year, month, day, carrier, dep_delay, air_time, distance)
c3 <- arrange(c2, year, month, day, carrier)
c4 <- mutate(c3, air_time_hours = air_time / 60)

## this will actually copy the data into R memory.
## only when you call the collect function explicitly, will it copy the data into memory.
carrierhours <- collect(c4)


str(carrierhours) ## this will be an R data frame. 

## performing pairwise t test
with(carrierhours, pairwise.t.test(air_time, carrier))

## ggplot will not work with spark tables.. the data needs to be loaded in R for plotting.
ggplot(carrierhours, aes(carrier, air_time_hours)) + geom_boxplot()

## or convert to data.frame without collecting at runtime to visualize
ggplot(as.data.frame(c4), aes(carrier, air_time_hours)) + geom_boxplot()


## Window functions

bestworst <- flights %>%
  group_by(year, month, day) %>%
  select(dep_delay) %>% 
  filter(dep_delay == min(dep_delay, na.rm = T) || dep_delay == max(dep_delay, na.rm = T))

## convert the dplyr operations to equivalent SQL code. 
dbplyr::sql_render(bestworst)


## Join operations
flights %>% left_join(airlines, by = 'carrier')


## taking sample from spark daata frames
sample_n(tbl = flights,size = 10,replace = F)
sample_frac(tbl = flights,size = 0.7,replace = F)

## use this to remove data frame from spark
dplyr::db_drop_table(sc, 'iris')

## Up side is that all the dplyr funtions are compatible with spark data frames and there is no 
## type casting or conversion needed.
## Downside is the visualition aspect. ggplot is not compatbile with spark DF so we need to load 
## the data in R and then perform visualization.
