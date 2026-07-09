`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/16/2026 01:57:36 PM
// Design Name: 
// Module Name: oledControl
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


module oledControl(
//oled interface
input clock,
input reset,

output wire oled_spi_clk,
output wire oled_spi_data,
//if using in the state machine set it to reg
output reg oled_vdd,
output reg oled_vbat,
output reg oled_reset_n,
output reg oled_dc_n,

input [6:0] sendData,
input sendDataValid,
output reg sendDone

    );
    
reg [4:0] state;
reg [4:0] nextState;
reg startDelay;
wire delayDone; // if it is a wire the value is coming for another module
reg spiLoadData;
reg [7:0] spiData;
wire spiDone;
// added after initialization
reg [1:0] currPage; //4 pages 0,1,2,3
wire [63:0] charBitMap;
reg [7:0] columnAddr;
reg [3:0] byteCounter;

localparam IDLE = 'd0,
           DELAY = 'd1,   
           INIT = 'd2,
           RESET = 'd3,
           CHARGE_PUMP = 'd4,
           WAIT_SPI = 'd5,
           CHARGE_PUMP1 = 'd6,
           PRE_CHARGE = 'd7,
           PRE_CHARGE1 = 'd8,
           VBAT_ON = 'd9,
           CONSTRAST = 'd10,
           CONSTRAST1 = 'd11,
           SEG_REMAP = 'd12,
           SCAN_DIR = 'd13,
           COM_PIN = 'd14,
           COM_PIN1 = 'd15,
           DISPLAY_ON = 'd16,
           FULL_DISPLAY = 'd17,
           DONE = 'd18,

           PAGE_ADDR = 'd19,
           PAGE_ADDR1 = 'd20,
           PAGE_ADDR2 = 'd21,
           COLUMN_ADDR = 'd22,
           SEND_DATA = 'd23;
    
//Have to follow OLED's specific sequence for initialization
always @(posedge clock)
begin
    if(reset)
    begin
        state <= IDLE;
        nextState<=IDLE;
        oled_vdd <= 1'b1;
        oled_vbat <= 1'b1;
        oled_reset_n <= 1'b1;
        oled_dc_n <= 1'b1;
        startDelay <= 1'b0;
        spiData <= 8'b0;
        spiLoadData <= 1'b0;
        //added for after initializationn sequence
        currPage <= 0;
        sendDone <= 0;
        columnAddr <= 0;
//added to reset
        byteCounter <= 4'd0;
    end   
    else
    begin
//added to there is an initialized value for needed signals on first clock cycle to Synthesis will keep the signals
        startDelay  <= 1'b0;
        spiLoadData <= 1'b0;
        case(state)
            IDLE:begin
                oled_vbat <= 1'b1;
                oled_reset_n <= 1'b1;
                oled_dc_n <= 1'b0; // bc will be sendind commands
                oled_vdd <= 1'b0; // power supply for logic is active low
                state <= DELAY;
                nextState <= INIT;
            end
            DELAY:begin
                startDelay <= 1'b1;
                if(delayDone)
                begin
                    state <=nextState;
                    startDelay <= 1'b0;
                end
            end
            INIT:begin
                spiData <= 'hAE;
                spiLoadData <= 1'b1;
                if(spiDone)
                    begin
                        spiLoadData <= 1'b0;
                        oled_reset_n <= 1'b0;
                        state <= DELAY;
                        nextState <= RESET;
                    end
                end
            RESET:begin
                oled_reset_n <= 1'b1;
                state <= DELAY;
                nextState <= CHARGE_PUMP;
            end
            CHARGE_PUMP:begin
                spiData <= 'h8D;
                spiLoadData <= 1'b1;
                if(spiDone)
                    begin
                        spiLoadData <= 1'b0;
                        state <= WAIT_SPI;
                        nextState <= CHARGE_PUMP1;
                    end
                end
             WAIT_SPI:begin
                if(!spiDone)
                begin
                    state <= nextState;
                end
             end
            CHARGE_PUMP1:begin
                spiData <= 'h14;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= PRE_CHARGE;
                end
             end
            PRE_CHARGE:begin
                spiData <= 'hD9;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= PRE_CHARGE1;
                end
             end
             PRE_CHARGE1:begin
                spiData <= 'hF1;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= VBAT_ON;
                end
             end
            VBAT_ON:begin
                oled_vbat <= 1'b0;
                state <= DELAY;
                nextState <= CONSTRAST;
            end
            CONSTRAST:begin
                spiData <= 'h81;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= CONSTRAST1;
                end
             end
            CONSTRAST1:begin
                spiData <= 'hFF;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= SEG_REMAP;
                end
             end
             SEG_REMAP:begin
                spiData <= 'hA0;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= SCAN_DIR;
                end
             end
             SCAN_DIR:begin
                spiData <= 'hC0;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= COM_PIN;
                end           
             end
             COM_PIN:begin
                spiData <= 'hDA;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= COM_PIN1;
                end           
             end
             COM_PIN1:begin
                spiData <= 'h00;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= DISPLAY_ON;
                end           
             end
             DISPLAY_ON:begin
                spiData <= 'hAF;
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <=  PAGE_ADDR;//FULL_DISPLAY;
                end           
             end
          //Initialization over
       /*      FULL_DISPLAY:begin
                spiData <= 'hA5; // Command will turn all of the screen on if initialization worked
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= DONE;
                end           
             end 
             DONE:begin
                state <= DONE;
             end    */
             PAGE_ADDR:begin
                spiData <= 'h22;
                spiLoadData <= 1'b1;
                oled_dc_n <= 1'b0;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= PAGE_ADDR1;
                end
            end
            PAGE_ADDR1:begin
                spiData <=currPage; //start page address
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    currPage <= currPage +1;
                    nextState <= PAGE_ADDR2;
                end
            end            
            PAGE_ADDR2:begin
                spiData <=currPage; //end address of page you are using 
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= COLUMN_ADDR;
                end
            end      
            COLUMN_ADDR:begin
                spiData <='h10; //start address of column you are using (hexadecimal) 
                spiLoadData <= 1'b1;
                if(spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    nextState <= DONE;
                end
            end  
            DONE:begin
                sendDone <= 1'b0; // !sendDone so that there has to be a clock cycle to occur so the 
                //sendDone is low when going to next logic and ready for next data when it comes            
                
                if(sendDataValid & columnAddr != 128 & !sendDone)
                begin
                    state <= SEND_DATA;
                    byteCounter <=8;
                end 
                //go to next page
                else if (sendDataValid & columnAddr == 128 & !sendDone)
                begin
                    state <= PAGE_ADDR;
                    byteCounter <=8;
                    columnAddr <=0;
                end
            end 
            // is data so the oled_dc_n should be on
            SEND_DATA:begin
                                //      upper  63       upper - 8,  so a byte @ a time
                spiData <= charBitMap[(byteCounter*8-1)-:8];
                spiLoadData <= 1'b1;
                oled_dc_n <= 1'b1;
                if(spiDone)
                begin
                    columnAddr <= columnAddr +1;
                    spiLoadData <= 1'b0;
                    state <= WAIT_SPI;
                    //check if have sent all 8 bytes fr the character
                    if(byteCounter !=1)
                    begin
                        byteCounter <= byteCounter -1;
                        nextState <= SEND_DATA;
                    end
                    else
                    begin
                        nextState <= DONE;
                        sendDone <= 1'b1;
                    end
                end
            end
            
            
            
            
            
            
            
        endcase
    end
     
end    
    
delayGen DG(
    .clock(clock), //1000MHz
    .delayEn(startDelay),
    .delayDone(delayDone)
    );
    
    
    
//spi interface and port mapping    
spiController SC(
    .clock(clock), // On-Board Znyq clock (100 MHz) can't change remember too fast forSPI of OLED
    .reset(reset),
    .data_in(spiData), // provided by other circuit 1 byte
    .load_data(spiLoadData), //Signal indicates new data for transmission
    .done_send(spiDone), // Signal indicate data has been sent over the spi interface
    .spi_clock(oled_spi_clk), // max is 10MHz max (OLED limit) only enable clock when there is data
    .spi_data(oled_spi_data)
    );    
    
charROM CR(
.addr(sendData), //char address of ASCII
.data(charBitMap)
    );  
    
    
    
    
    
    
endmodule
