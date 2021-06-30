# simple-scalable-ml-backend

#### Abstract

The idea of the project is that we deploy a lot of workers to process a certain data array from the master node. 

We decided to make a master node with NFS sharing, which is simple for the scaling group (this can be AWS group),
where a lot of launched images simply mount the ready-made backend on read-only for themselves.
We tried to organize logging of the process by means of the database - there is a VIEW active_workers.

#### Database schema description

We are using self-made locking-based queue. When worker will request new record,
according to the set priorities, there will be a queue, so in inexpensive environment
workers sequentially take records with an approximate delay of 10ms, this is time difference between the two requests (in or AWS tests).
In case of concurrent update (serialization_failure - could not serialize access due to concurrent update ),
worker just restarts or call get_unprocessed_entry_by_priority function again in a handler.

Queue is in files.files table in status, which is worker_id when backend in launched,
you can review comments in schema sh_db0_schema_creation_script.sql 
This is roughly the minimum database scheme for such typical backends.

If some worker tries to take the same record (call files.get_unprocessed_entry_by_priority function)
together with some another worker, there will be transaction rollback, the worker should be restarted,
just because it is impossible to open transactions within a function,
this (retry/restart) should be done at the application level. 
Either the handler must be in the python code, or at the parent level of bash script,
in our case this is workers_launcher.sh and just in case of any unhandled exception,
a restart will follow, for us such time was not so critical,
because for our task the backend worked on one record on average 30 mins.

We are using Postgresql because it has good enough high availability solutions, such as Stolon.

#### Deploying HA infrastructure

We offer to use MinIO as S3 compatible storage.
The official repository shows sample with 4 minio distributed instances https://github.com/minio/minio/tree/master/docs/orchestration/docker-compose
For downloading and uploading any data that needs to be processed check the MinIO python client quickstart guide https://docs.min.io/docs/python-client-quickstart-guide

For HA Postgresql deployment we suggest to use Stolon with PgBouncer https://github.com/gocardless/stolon-pgbouncer
