# (c) MIT License 2021 hcl14, ashd97

import sys
print(sys.version)
import time
import psycopg2
from psycopg2 import extensions # extensions.ISOLATION_LEVEL_SERIALIZABLE
import os, shutil, pandas as pd
from schrodinger.pipeline.pipeline import Pipeline
import traceback


worker_db = os.environ['WORKER_DB']
user = os.environ['WORKER_USER']
password = os.environ['WORKER_PASSWORD']
db_host = os.environ['WORKER_DB_HOST']
worker_grid = os.environ['WORKER_GRID']

def single_connection_query(check_sql, fetch=True, queue_concurrent=False):
    conn = psycopg2.connect(dbname=worker_db, user=user, 
                        password=password, host=db_host)
    cursor = conn.cursor()
    if queue_concurrent:
         conn.set_isolation_level(extensions.ISOLATION_LEVEL_SERIALIZABLE)
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


# conn.autocommit = True # does not work normally

end_status = -1 # status indicating that job is done
pipeline_file = "test_pipeline.txt" # must be present in a working dir
grid_file = worker_grid

check_sql = """SELECT * FROM files.number_of_unprocessed_records;"""

res = single_connection_query(check_sql)
print("Worker sees", res, "unprocessed records")



def worker(worker_id):
    # Those directories are intended to be in RAM
    d = f"worker_tmp{worker_id}"
    if os.path.exists(d):
        shutil.rmtree(d)
    # static dir to store static files, to avoid getting 
    # error when they are opened by someone else
    d1 = f"worker_tmp{worker_id}_static"
    if os.path.exists(d1):
        shutil.rmtree(d1)
    os.mkdir(d1)
    shutil.copyfile(pipeline_file, os.path.join(d1,pipeline_file)) 
    shutil.copyfile(grid_file, os.path.join(d1,grid_file)) 
    
    # clean all records with id of this worker (past fails?)
    
    clean_update = f"""SELECT files.clean_records_for_worker ({worker_id});"""
    single_connection_query(clean_update, False, True) 
    
    
    res = single_connection_query(check_sql)
    print("Cleaned: Worker sees", res, "worker records (-1 is correct)")

    
    while True:
        try:
            time.sleep(2) # delay for checking db
        
            # go check gatabase for new smiles to process
            # lock one of the entries with UPDATE, setting worker id as status
            
            # We need to debug this operation
            # conn.set_isolation_level(3)
            
            print("We will try to run over here get_unprocessed_entry")
            clean_update = f"""SELECT files.get_unprocessed_entry_by_priority ({worker_id});"""
            
            res = single_connection_query(clean_update, True, True) 
            print(res)
            
            
            try:
                res = res[0][0]
                assert res >= -2
            except Exception as e:
                just_the_string = traceback.format_exc()
                print(just_the_string)
                print("Something nasty is going on, function must return -2, -1, or nonnegative")
                sys.exit()
            
            if res == -1:
                # we have not updated anything, no rows to process
                print("Wrong isolation level for .get_unprocessed_entry_by_priority !")
                sys.exit()
            if res == -2:
                print("No records to process, waiting....")
                continue
                
            # else, res is the ide of the record to process.
            # it is already reserver for the worker
                
            # Now fetch the record safely
            # id is a key, so it should be fast
            record_select = f"""select * 
                    from files.files 
                    WHERE id = {res};"""
        
            res = single_connection_query(record_select, True, False) 
            
            print(res)
            
            # res > 1 will never execute, because we have limit 1 above
            if len(res) == 0 or len(res)> 1:
                print("Something nasty is going on. Do you have multiple workers with same id or have not cleaned the DB after stopping?")
                sys.exit()

            res = res[0]
            
            p = Pipeline()
            
            record_id = res[0]
            sm = res[1]
            print(sm)
            os.mkdir(d)
            os.chdir(d)
            print("current working directory", os.getcwd())
            with open("ligand_smiles.smi", 'w') as f:
                f.write(sm)
            shutil.copyfile(os.path.join("..", d1, pipeline_file), pipeline_file)
            shutil.copyfile(os.path.join("..", d1, grid_file), grid_file)
            p.readFile(pipeline_file)
            try:
                p.run()
                pipeline_pass = True
            except Exception as e:
                just_the_string = traceback.format_exc()
                print(just_the_string)
                print('pipeline failed!')
                pipeline_pass = False


        
            print("Finished, trying to get result")
            
            try:
                assert pipeline_pass is True
                df = pd.read_csv('pipeline-XP_OUT_1.csv')                
                df = df.sort_values(by=['r_i_docking_score'])            
                best_score = df['r_i_docking_score'][0]            
                num_conformers = len(df)                
                print("Got {} results".format(num_conformers))
                
                dres = True
                
            except Exception as e:
                just_the_string = traceback.format_exc()
                print(just_the_string)
                
                print("No docking result!")
                dres = False
                
            # sending data back to DB
            # Function receiving end_status + docking_score + num_conformers + id + worker_id
            if dres is True:            
                test_of_record_update = f"""select files.set_worker_result('-1',
                                            '{best_score}',
                                            '{num_conformers}',
                                            '{record_id}',
                                            '{worker_id}');"""
            else:
                test_of_record_update = f"""select files.set_worker_result('0',
                                            '0.0',
                                            '0',
                                            '{record_id}',
                                            '{worker_id}');"""
            
            res = single_connection_query(test_of_record_update, "rowcount", False) 
            
            print(res)
            
            try:            
                assert res in [-1,1]
            except Exception as e:
                just_the_string = traceback.format_exc()
                print(just_the_string)
                
                print("something nasty is going on! Function must always return -1 or 1")
                sys.exit()
                
            if res == -1:
                print("Record not updated! Problem with DB. Exiting for now (debug mode)")
                sys.exit()
            
            os.chdir("..")   
            shutil.rmtree(d)
            print("returning to root directory", os.getcwd())
            
        except KeyboardInterrupt:
            print("Bye")
            sys.exit()    


if __name__ == "__main__":
    
    check_sql = "select files.add_worker()"
    res = single_connection_query(check_sql, fetch=True, queue_concurrent=True)
    print(res)
    try:
        worker_id = res[0][0]
        print(f"Assiging worker id {worker_id}")
        
    except Exception as e:
        just_the_string = traceback.format_exc()
        print(just_the_string)
        sys.exit()  
        
        
    print("Starting worker id {}. Make sure there is no other worker with this id! \nPress Ctrl+C to stop gracefully".format(worker_id))
    
    
    worker(worker_id)
