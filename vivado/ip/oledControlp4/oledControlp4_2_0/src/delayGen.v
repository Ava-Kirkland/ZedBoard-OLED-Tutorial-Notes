`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/16/2026 02:19:04 PM
// Design Name: 
// Module Name: delayGen
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


module delayGen(
    input clock, //1000MHz
    input delayEn,
    output reg delayDone
    );
    
//1/100MHz =     1e-8
// 2 miliseconds .002 / 1e-8 = 200,000
//Count to 200,000 in Binary 0011 0000 1101 0100 0000, 18 bits
reg [17:0] counter;

always @(posedge clock)
begin
    if(delayEn & counter != 200000)
        counter <= counter +1;
    else
        counter <= 0;
end

always @(posedge clock)
begin
    if(delayEn & counter == 200000)
        delayDone <= 1'b1;
    else
        delayDone <= 1'b0;    
end

endmodule
