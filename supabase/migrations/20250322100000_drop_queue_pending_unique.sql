-- Allow multiple pending queue entries per boat.
drop index if exists boat_launch_queue_unique_pending;
