using Test
using AuctionKit
using UUIDs
using Dates

@testset "AuctionKit.jl Tests" begin
    
    @testset "Event Log Tests" begin
        # Create event log
        log = CentralizedEventLog()
        auction_id = uuid4()
        
        # Test event creation and appending
        event = BidSubmittedEvent(
            uuid4(),
            auction_id,
            uuid4(),
            100.0,
            1,
            now(),
            Dict{Symbol, Any}()
        )
        
        appendEventToLog(log, auction_id, event)
        
        # Query events
        events = queryEventsByAuction(log, auction_id)
        @test length(events) == 1
        @test events[1].wrapped_event == event
        
        # Test chain hash verification
        @test verifyLogIntegrity(log)
    end
    
    @testset "Auction Mechanisms" begin
        
        @testset "First Price Auction" begin
            mechanism = FirstPriceAuction(
                reserve_price = 10.0,
                tie_breaking = :random,
                max_winners = 1
            )
            
            # Create test bids
            bids = [
                Bid(uuid4(), 15.0, 1),
                Bid(uuid4(), 20.0, 1),
                Bid(uuid4(), 12.0, 1)
            ]
            
            clearing_price = determineClearingPrice(mechanism, bids)
            @test clearing_price == 20.0
            
            winners, allocations = allocateWinners(mechanism, bids, clearing_price)
            @test length(winners) == 1
            @test winners[1] == bids[2].bidder_id
        end
        
        @testset "Vickrey Auction" begin
            mechanism = VickreyAuction(
                reserve_price = 10.0,
                tie_breaking = :random
            )
            
            bids = [
                Bid(uuid4(), 15.0, 1),
                Bid(uuid4(), 20.0, 1),
                Bid(uuid4(), 12.0, 1)
            ]
            
            clearing_price = determineClearingPrice(mechanism, bids)
            @test clearing_price == 15.0  # Second highest bid
            
            winners, allocations = allocateWinners(mechanism, bids, clearing_price)
            @test length(winners) == 1
            @test winners[1] == bids[2].bidder_id  # Highest bidder wins
            
            payments = calculatePayments(mechanism, winners, allocations, clearing_price)
            @test payments[winners[1]] == 15.0  # Pays second price
        end
        
        @testset "Dutch Auction" begin
            mechanism = DutchAuction(
                starting_price = 100.0,
                decrement = 10.0,
                floor_price = 50.0,
                tick_duration = 0.001,  # Very short for testing
                max_quantity = 2
            )
            
            # Wait for price to drop
            sleep(0.002)
            updateCurrentPrice(mechanism)
            @test mechanism.current_price < 100.0
            
            bids = [
                Bid(uuid4(), 80.0, 1),
                Bid(uuid4(), 85.0, 1)
            ]
            
            clearing_price = determineClearingPrice(mechanism, bids)
            winners, allocations = allocateWinners(mechanism, bids, clearing_price)
            
            @test length(winners) <= 2
        end
        
        @testset "English Auction" begin
            mechanism = EnglishAuction(
                starting_price = 10.0,
                increment = 5.0,
                inactive_duration = 1.0
            )
            
            bid1 = Bid(uuid4(), 15.0, 1)
            bid2 = Bid(uuid4(), 20.0, 1)
            
            success1, msg1 = acceptEnglishBid(mechanism, bid1)
            @test success1
            @test mechanism.current_leader == bid1.bidder_id
            
            success2, msg2 = acceptEnglishBid(mechanism, bid2)
            @test success2
            @test mechanism.current_leader == bid2.bidder_id
            @test mechanism.current_price == 20.0
        end
    end
    
    @testset "Auction Actor" begin
        # Create event log
        event_log = CentralizedEventLog()
        
        # Create auction actor
        actor = createAuctionActor(
            :first_price,
            Dict{Symbol, Any}(
                :reserve_price => 10.0,
                :start_time => now(),
                :end_time => now() + Dates.Second(10)
            );
            event_log = event_log
        )
        
        # Start auction
        actor.state.status = :active
        
        # Submit bid
        msg = BidMessage(
            uuid4(),
            actor.state.auction_id,
            15.0,
            1,
            Dict{Symbol, Any}(),
            now()
        )
        
        sendMessageToActor(actor, msg)
        sleep(0.1)  # Allow processing
        
        @test length(actor.state.current_bids) == 1
        
        # Finalize auction
        finalize_msg = FinalizeMessage(false, now())
        sendMessageToActor(actor, finalize_msg)
        sleep(0.1)
        
        @test actor.state.status == :completed
        @test !isnothing(actor.state.result)
        
        # Clean up
        stopActorGracefully(actor)
    end
    
    @testset "Auction Controller" begin
        # Create controller
        controller = AuctionController{Float64}()
        
        # Create simple workflow
        configs = [
            Dict{Symbol, Any}(
                :auction_type => :first_price,
                :reserve_price => 10.0,
                :duration_seconds => 0,
                :initial_bids => [
                    Dict(:bidder_id => uuid4(), :amount => 15.0, :quantity => 1),
                    Dict(:bidder_id => uuid4(), :amount => 20.0, :quantity => 1)
                ]
            ),
            Dict{Symbol, Any}(
                :auction_type => :vickrey,
                :reserve_price => 15.0,
                :duration_seconds => 0,
                :propagate_winners => true
            )
        ]
        
        # Chain auctions
        result = chainAuctions(controller, configs)
        
        @test length(result.node_results) == 2
        @test result.execution_order[1] in keys(result.node_results)
        @test result.execution_order[2] in keys(result.node_results)
        
        # Clean up
        stopController(controller)
    end
    
    @testset "Bid Submission Interfaces" begin
        
        @testset "Direct Interface" begin
            controller = AuctionController{Float64}()
            interface = DirectBidInterface(controller)
            
            # Create auction
            result = createAuctionDirect(
                interface,
                :first_price,
                Dict{Symbol, Any}(:reserve_price => 10.0)
            )
            
            @test result[:success]
            auction_id = result[:auction_id]
            
            # Submit bid
            bid_result = submitDirectBid(
                interface,
                auction_id,
                uuid4(),
                15.0,
                1
            )
            
            @test bid_result[:success]
            
            # Finalize
            final_result = finalizeAuctionDirect(interface, auction_id)
            @test final_result[:success]
            @test final_result[:clearing_price] == 15.0
            
            stopController(controller)
        end
        
        @testset "RPC Interface" begin
            controller = AuctionController{Float64}()
            interface = RPCBidInterface(
                controller;
                port = 8888,
                host = "127.0.0.1"
            )
            
            # Start server
            startRPCServer(interface)
            sleep(0.5)  # Allow server to start
            
            # Test RPC bid submission
            # Note: In a real test, you would make HTTP requests
            # Here we just verify the server started
            @test !isnothing(interface.server)
            
            # Stop server
            stopRPCServer(interface)
            stopController(controller)
        end
    end
    
    @testset "Workflow Graph" begin
        controller = AuctionController{Float64}()
        
        # Create workflow graph
        configs = [
            Dict{Symbol, Any}(
                :auction_type => :first_price,
                :reserve_price => 10.0
            ),
            Dict{Symbol, Any}(
                :auction_type => :second_price,
                :reserve_price => 12.0
            )
        ]
        
        graph = createWorkflowGraph(controller, configs)
        
        @test length(graph.nodes) == 2
        @test validateDAGStructure(graph)
        
        # Test topological sort
        order = topologicalSortWorkflow(graph)
        @test length(order) == 2
        
        stopController(controller)
    end
    
end

println("All tests passed!")