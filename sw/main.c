#include "oled.h"
#include <stdio.h>
#include <xparameters.h>
#include "sleep.h"

int main (){
    // a way of declaring a string in C
    char *myString = "Hello World";
    oledControl myOled;
    initOled(&myOled, XPAR_OLEDCONTROLP4_0_BASEADDR);
    clearOled(&myOled);
    printOled(&myOled, myString);
    // char buffer[4];   // enough for "99\0"

    // for(int i = 0; i < 100; i++){
    //     sprintf(buffer, "%d", i);
    //     printOled(&myOled, buffer);
    //     sleep(1);
    // }
}