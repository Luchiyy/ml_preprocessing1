EXTENSION = ml_preprocessing
MODULE_big = ml_preprocessing
OBJS = ml_preprocessing.o missing_values_pg.o standardize_pg.o standardize_core.o \
       one_hot_pg.o one_hot_core.o
DATA = ml_preprocessing--1.0.sql
SHLIB_LINK += -lm

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

standardize_pg.o standardize_core.o: standardize_core.h
one_hot_pg.o one_hot_core.o: one_hot_core.h
