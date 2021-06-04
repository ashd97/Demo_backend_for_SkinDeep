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

conn = psycopg2.connect(dbname='sh_db0_dev', user='shworker', 
                        password='shworker', host='localhost')
cursor = conn.cursor()
'''
cursor.execute("DROP TABLE IF EXISTS public.files")
conn.commit()

cursor.execute(""" CREATE TABLE public.files (
    id integer NOT NULL,
    smiles character varying(255),
    num_conformers integer,
    docking_score real,
    start_ts timestamp with time zone,
    stop_ts timestamp with time zone,
    status integer DEFAULT 0
);
""")

cursor.execute(""" ALTER TABLE ONLY public.files
    ADD CONSTRAINT _records_id_unique UNIQUE (id);""")
    
cursor.execute(""" 
CREATE INDEX _smiles_idx ON public.files USING btree (smiles);""")

cursor.execute(""" 
CREATE INDEX _starts_idx ON public.files USING btree (start_ts);""")

cursor.execute(""" 
CREATE INDEX _stops_idx ON public.files USING btree (stop_ts);""")

cursor.execute(""" 
CREATE INDEX _status_idx ON public.files USING btree (status);""")

conn.commit() # let's not use conn.autocommit

'''
# Test fill DB

smiles = []

idx = 0
with open('rna_base.smi','r') as f:
    for line in f:
        if len(line) > 2:
            idx += 1
            smiles.append((idx, line.strip() ))
            

#import pandas as pd
#df = pd.read_csv('rna_base.smi')

#for idx, s in enumerate(df['SMILES']):
#    smiles.append((idx, s.strip() ))

print(len(smiles))


insert_query = 'insert into files.files (id, smiles) values %s'
extras.execute_values (
    cursor, insert_query, smiles, template=None, page_size=100
)

conn.commit()


cursor.close()
conn.close()