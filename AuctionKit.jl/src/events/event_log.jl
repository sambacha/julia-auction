# Centralized event log with immutability and chain hashing
# Following A/HC/LC naming pattern

"""
    CentralizedEventLog

An immutable, append-only event log with chain hashing for audit trail.
"""
mutable struct CentralizedEventLog
    events::Vector{ImmutableEvent}
    index::Dict{UUID, Vector{Int}}  # auction_id -> event indices
    type_index::Dict{DataType, Vector{Int}}  # event type -> event indices
    lock::ReentrantLock
    checkpoints::Vector{Tuple{DateTime, Int}}  # (timestamp, event_index)
    
    function CentralizedEventLog()
        new(
            Vector{ImmutableEvent}(),
            Dict{UUID, Vector{Int}}(),
            Dict{DataType, Vector{Int}}(),
            ReentrantLock(),
            Vector{Tuple{DateTime, Int}}()
        )
    end
end


# A/HC/LC: append + Event + ToLog
function append_event_to_log(log::CentralizedEventLog, auction_id::UUID, event::AuctionEvent)::UUID
    lock(log.lock) do
        # Get previous hash
        previous_hash = isempty(log.events) ? UInt8[] : log.events[end].event_hash
        
        # Create immutable event
        immutable_event = ImmutableEvent(auction_id, event, previous_hash)
        
        # Append to log
        push!(log.events, immutable_event)
        event_index = length(log.events)
        
        # Update indices
        if !haskey(log.index, auction_id)
            log.index[auction_id] = Int[]
        end
        push!(log.index[auction_id], event_index)
        
        # Update type index
        event_type = typeof(event)
        if !haskey(log.type_index, event_type)
            log.type_index[event_type] = Int[]
        end
        push!(log.type_index[event_type], event_index)
        
        return immutable_event.id
    end
end

# A/HC/LC: query + Events + ByAuction
function queryEventsByAuction(log::CentralizedEventLog, auction_id::UUID)::Vector{ImmutableEvent}
    lock(log.lock) do
        indices = get(log.index, auction_id, Int[])
        return [log.events[i] for i in indices]
    end
end

# A/HC/LC: query + Events + ByType
function queryEventsByType(log::CentralizedEventLog, event_type::DataType)::Vector{ImmutableEvent}
    lock(log.lock) do
        indices = get(log.type_index, event_type, Int[])
        return [log.events[i] for i in indices]
    end
end

# A/HC/LC: replay + Events + FromLog
function replayEventsFromLog(log::CentralizedEventLog, auction_id::UUID)::Vector{ImmutableEvent}
    return queryEventsByAuction(log, auction_id)
end

# A/HC/LC: get + Events + AfterTimestamp
function getEventsAfterTimestamp(log::CentralizedEventLog, timestamp::DateTime)::Vector{ImmutableEvent}
    lock(log.lock) do
        return filter(e -> e.timestamp > timestamp, log.events)
    end
end

# A/HC/LC: verify + Log + Integrity
function verifyLogIntegrity(log::CentralizedEventLog)::Bool
    lock(log.lock) do
        if isempty(log.events)
            return true
        end
        
        # First event should have empty previous hash
        if !isempty(log.events[1].previous_hash)
            return false
        end
        
        # Verify chain integrity
        for i in 2:length(log.events)
            if log.events[i].previous_hash != log.events[i-1].event_hash
                return false
            end
        end
        
        return true
    end
end

# A/HC/LC: create + Checkpoint + AtIndex
function createCheckpointAtIndex(log::CentralizedEventLog, index::Int)
    lock(log.lock) do
        if index > 0 && index <= length(log.events)
            timestamp = log.events[index].timestamp
            push!(log.checkpoints, (timestamp, index))
        end
    end
end

# A/HC/LC: restore + From + Checkpoint
function restoreFromCheckpoint(log::CentralizedEventLog, checkpoint_index::Int)::CentralizedEventLog
    lock(log.lock) do
        if checkpoint_index > 0 && checkpoint_index <= length(log.checkpoints)
            checkpoint = log.checkpoints[checkpoint_index]
            event_index = checkpoint[2]
            
            # Create new log with events up to checkpoint
            new_log = CentralizedEventLog()
            new_log.events = log.events[1:event_index]
            
            # Rebuild indices
            for (i, event) in enumerate(new_log.events)
                if !haskey(new_log.index, event.auction_id)
                    new_log.index[event.auction_id] = Int[]
                end
                push!(new_log.index[event.auction_id], i)
            end
            
            return new_log
        end
        
        return log
    end
end

# A/HC/LC: export + Events + ToJSON
function exportEventsToJSON(log::CentralizedEventLog, filepath::String)
    lock(log.lock) do
        events_data = []
        for event in log.events
            push!(events_data, Dict(
                :id => string(event.id),
                :auction_id => string(event.auction_id),
                :event_type => string(typeof(event.wrapped_event)),
                :event => event.wrapped_event,
                :hash => bytes2hex(event.event_hash),
                :previous_hash => bytes2hex(event.previous_hash),
                :timestamp => event.timestamp
            ))
        end
        
        open(filepath, "w") do io
            JSON3.pretty(io, events_data)
        end
    end
end