#include "oled.h"
#include<xil_io.h>

int initOled(oledControl*myOled,u32 baseAddress){
    myOled->baseAddress = baseAddress;
    return 0;
}

void writeCharOled(oledControl *myOled, char myChar){
    u32 status = 0;
    Xil_Out32(myOled->baseAddress+8,myChar);
    Xil_Out32(myOled->baseAddress,0x1);
    while(!status){
        // xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
        // Xil_In32(myOled->baseAddress+0),
        // Xil_In32(myOled->baseAddress+4),
        // Xil_In32(myOled->baseAddress+8),
        // Xil_In32(myOled->baseAddress+12));
        status = Xil_In32(myOled->baseAddress+4); //polling
    }
    Xil_Out32(myOled->baseAddress+4,0x0);
}

void printOled(oledControl *myOled, char *myString){
    while(*myString != 0){
        //myOled is a pointer
        // using a pointer of a pointer
        writeCharOled(myOled, *myString);
        myString++;//increament the starting address point of the pointer
    }
}

void clearOled(oledControl *myOled){
    //4 pages * 16 characters = 64 characters
    u32 i;
    for(i=0; i<64; i++){
        writeCharOled(myOled,' ');
    }
}