import sys
print(sys.version)
import psycopg2
import pandas as pd


# In win powershell as admin:
# >Set-Location -Path "C:\Program Files\Schrodinger2020-3"
# >Set-ExecutionPolicy RemoteSigned
# >schrodinger.ve\Scripts\activate

# or source schrodinger.ve/bin/activate on unix

# cd worker

conn = psycopg2.connect(dbname='sh_db0_dev', user='shworker', 
                        password='shworker', host='localhost')
cursor = conn.cursor()

print("\n")

# get number of processed records

query = """SELECT * FROM files.number_of_processed_records;"""
        
cursor.execute(query)
res = cursor.fetchall()

all_records= """SELECT * from files.number_of_unprocessed_records;"""

cursor.execute(all_records)
res1 = cursor.fetchall()

print("Pocessed records so far", res[0][0], "/", res1[0][0])



print("\n")


query = """SELECT * from files.best LIMIT 10;"""

cursor.execute(query)
res = cursor.fetchall()
print("Best records:")
df = pd.DataFrame(res, columns =['id', 'SMILES', 'Score', 'created', 'delay'])
print(df)


print("\n")
