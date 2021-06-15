You can run postgres db in a docker, but from a subjective point of view, you really need this if there is a need to limit app memory.
Postgres has enough HA solutions, like Stolon, Patroni.

This is just a sample. So cd to this folder then run

docker-compose up -d

And then check does port forwarding works the

sudo netstat -plnt | grep ':5432'

Attach to specific launched container to check the initialization: 

docker ps -a

docker exec -it CONTAINER_ID /bin/bash
