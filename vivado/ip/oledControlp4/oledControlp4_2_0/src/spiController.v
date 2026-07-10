`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Ava Kirkland
// 
// Create Date: 06/16/2026 08:51:00 AM
// Design Name: 
// Module Name: spiController
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//SPI has handshking between devices, when data is sent to a device the receiving device tells the transmitting device that they got the data
module spiController(
input clock, // On-Board Znyq clock (100 MHz) can't change remember too fast forSPI of OLED
input reset,
input [7:0] data_in, // provided by other circuit 1 byte
input load_data, //Signal indicates new data for transmission
output reg done_send, // Signal indicate data has been sent over the spi interface
output spi_clock, // max is 10MHz max (OLED limit) only enable clock when there is data
output reg spi_data
    );
   //5 cycles of input clock per toggle
    //10 cycles per full SPI clock period 
    // so 100MHz / 10 = 10 MHz
reg [2:0] counter = 0; // 3 bits so can count to 4
reg [2:0] dataCounter; 
reg [7:0] shiftReg;
//attribute is software based not Verilog based
reg [1:0] state;  //2 flip flops
reg clock_10;
reg CE; // clock enabled

//multiplexer
assign spi_clock = (CE ==1) ? clock_10 : 1'b1;

//constants
localparam IDLE = 'd0,
           SEND = 'd1,
           DONE = 'd2;

always @(posedge clock)
begin
    if(counter != 4)
        counter <= counter +1;
    else
        counter <=0;

end

//For asymulation need initialize it for hardware don't need to
initial 
    clock_10 <=0;

always @(posedge clock)
begin
    if(counter == 4)
        clock_10 <= ~clock_10;
    
end    

//state machine
//At state it all happens on the same clock edge
always @(negedge clock_10)
begin
    if(reset)
    begin
        state <= IDLE;
        dataCounter <= 0;
        done_send <= 1'b0;
        CE <= 0;
        spi_data <= 1'b0;
    end
    else
    begin
        case(state)
            IDLE:begin
                if(load_data)
                begin   
                    shiftReg <= data_in;
                    state <= SEND;
                    dataCounter <= 0;
                end
            end 
            SEND:begin
                spi_data <= shiftReg[7]; //MSB first
                shiftReg <= {shiftReg[6:0],1'b0} ;
                //shift all to left so 6th place go 7th, and the right valueis a 0
                CE <= 1;
                if(dataCounter != 7)
                    dataCounter <= dataCounter +1;
                else
                begin
                    state <= DONE;
                end 
            end                    
        DONE:begin
                done_send <= 1'b1;
                CE <= 0;
                if(!load_data)
                begin
                    done_send <= 1'b0;
                    state <= IDLE;
                end
            end            
        endcase                             
            
    end
end

endmodule
