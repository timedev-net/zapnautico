-- Allow multiple pending queue entries per embarcação.
drop index if exists boat_launch_queue_unique_pending;
