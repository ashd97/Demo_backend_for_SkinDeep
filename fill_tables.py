import psycopg2
from psycopg2 import sql, extras

# If there is no venv, run schrodinger_virtualenv.py schrodinger.ve to install pycopg2

# In win powershell as admin:
# >Set-Location -Path "C:\Program Files\Schrodinger2020-3"
# >Set-ExecutionPolicy RemoteSigned
# >schrodinger.ve\Scripts\activate

# or source schrodinger.ve/bin/activate on unix

# Set-Location -Path "C:\Program Files\Schrodinger2020-3\myscripts_sequential"

# This file creates and populates DB, pipeline.py is worker test

# CREATE DATABASE sh_db0

def single_connection_query(check_sql, fetch=True, queue_concurrent=False, dbname='sh_db0_dev', values=[], user='shworker', password='shworker'):
    conn = psycopg2.connect(dbname=dbname, user=user, 
                        password=password, host='localhost')
    cursor = conn.cursor()
    if queue_concurrent:
         conn.set_isolation_level(extensions.ISOLATION_LEVEL_SERIALIZABLE)
         
    if len(values) > 0:
        extras.execute_values (
        cursor, insert_query, values, template=None, page_size=100
        )
        conn.commit()
    else:
        cursor.execute(check_sql)
        conn.commit()
    if isinstance(fetch, bool):
        if fetch is True:
            res = cursor.fetchall()
            return res
    else:
        if fetch == "rowcount":
            res = cursor.rowcount
            return res

'''
query = "select * from files.files;"

res = single_connection_query(query, True, dbname="sh_db0_dev", user='shworker', password='shworker')
print("Fetched!", len(res))


res = [list(r) for r in res]
print("converted")


# Test fill DB

ids = [rec[0] for rec in res]

import random

random.shuffle(ids)

to_insert = []

for idx, item in enumerate(res):
    item1 = item
    item1[0] = ids[idx]
    to_insert.append(item1)
'''

inserts = []
ids = 1602
with open("/home/ubuntu/pres_sub/preserved_substructure_6","r") as f:
	for line in f:
		line = line.strip()
		if len(line) > 3:
			inserts.append((line, None,None,None,None,0,1))
			ids += 1
 
to_insert = inserts    
insert_query = 'insert into files.files (smiles,num_conformers,docking_score,start_ts,stop_ts,status,priority) values %s'

single_connection_query(insert_query, fetch=False, dbname='sh_db0_dev', values = to_insert)
print(ids)
