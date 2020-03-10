/*
 * tuxctl-ioctl.c
 *
 * Driver (skeleton) for the mp2 tuxcontrollers for ECE391 at UIUC.
 *
 * Mark Murphy 2006
 * Andrew Ofisher 2007
 * Steve Lumetta 12-13 Sep 2009
 * Puskar Naha 2013
 */

#include <asm/current.h>
#include <asm/uaccess.h>

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/miscdevice.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/spinlock.h>

#include "tuxctl-ld.h"
#include "tuxctl-ioctl.h"
#include "mtcp.h"

/* the hex for LED*/
#define ZERO  0xE7
#define ONE   0x06
#define TWO   0xCB
#define THREE 0x8F
#define FOUR  0x2E
#define FIVE  0xAD
#define SIX   0xED
#define SEVEN 0x86
#define EIGHT 0xEF
#define NINE  0xAE
#define NUM_A 0xEE
#define NUM_B 0x6D
#define NUM_C 0xE1
#define NUM_D 0x4F
#define NUM_E 0xE9
#define NUM_F 0xE8

char time_info(unsigned long arg, char on);

static spinlock_t lock_tux = SPIN_LOCK_UNLOCKED;
unsigned button_info;
int ack;
unsigned long time_backup;

#define debug(str, ...) printk(KERN_DEBUG "%s: " str, __FUNCTION__, ## __VA_ARGS__)

/************************ Protocol Implementation *************************/

/* tuxctl_handle_packet()
 * IMPORTANT : Read the header for tuxctl_ldisc_data_callback() in
 * tuxctl-ld.c. It calls this function, so all warnings there apply
 * here as well.
 */
void tuxctl_handle_packet (struct tty_struct* tty, unsigned char* packet) {
    unsigned a, b, c;

    a = packet[0]; /* Avoid printk() sign extending the 8-bit */
    b = packet[1]; /* values when printing them. */
    c = packet[2];

    switch (a)
    {
        case MTCP_ACK:
        {
          spin_lock(&lock_tux);
          ack = 0;
          spin_unlock(&lock_tux);
          break;
        }

        case MTCP_BIOC_EVENT:   /* make the left and down back */
        {
          char switch1 = 0x00;
          char switch2 = 0x00;
          char temp = c;
          int cba = temp & 0x09;
          char abc = b;
          switch1 = (temp & 0x04)>>1;
          switch2 = (temp & 0x02)<<1;
          cba = cba | switch1;
          cba = cba | switch2;
          cba = cba<<4;
          abc = abc & 0x0F;
          spin_lock(&lock_tux);
          button_info = cba + abc;
          spin_unlock(&lock_tux);
          break;
        }

        case MTCP_RESET:
        {
          int index = 0;
          unsigned long temp1,temp,temporary;
          char bitmask;
          int a;
          char buffer[10];
          buffer[0] = MTCP_LED_USR;
          buffer[1] = MTCP_BIOC_ON;
          a = tuxctl_ldisc_put(tty, buffer, 2);
          if (a != 0)
          {
            return;
          }
          spin_lock(&lock_tux);   /*get the  lock */
          temp = time_backup;
          if (ack == 1)
          {
            spin_unlock(&lock_tux);  /* unlock */
            return;
          }
          spin_unlock(&lock_tux);       /* unlcok*/

          spin_lock(&lock_tux);      /*get the  lock */
          temporary = time_backup;
          button_info = 0;
          if (ack == 1)
          {
            spin_unlock(&lock_tux);       /* unlcok*/
            return;
          }
          spin_unlock(&lock_tux);           /* unlcok*/
          temp1 = temporary>>16;
          bitmask = temp1 & 0x0F;
          buffer[0] = MTCP_LED_SET;
          buffer[1] = 0x0F;
          index = 2;
          if (bitmask & 0x08)   /* set the led in order*/
          {
            char led3 = time_info(temporary & 0x0F, temporary>>20 & 0x10);  /* call set led  function */

            buffer[index] = led3;
            index++;
          }
          else
          {
            char led3 = time_info(0xFF, temporary>>20 & 0x10);       /* store the command value into led variable to display*/

            buffer[index] = led3;
            index++;
          }
          if (bitmask & 0x04)
          {
            char led2 = time_info(temporary>>4 & 0x0F, temporary>>21 & 0x10);   /* store the command value into led variable to display*/

            buffer[index] = led2;
            index++;
          }
          else
          {
            char led2 = time_info(0xFF, temporary>>21 & 0x10);   /* store the command value into led variable to display*/

            buffer[index] = led2;
            index++;
          }
          if (bitmask & 0x02)
          {
            char led1 = time_info(temporary>>8 & 0x0F, temporary>>22 & 0x10);   /* store the command value into led variable to display*/

            buffer[index] = led1;
            index++;
          }
          else
          {
            char led1 = time_info(0xFF, temporary>>22 & 0x10);    /* store the command value into led variable to display*/

            buffer[index] = led1;
            index++;
          }
          if (bitmask & 0x01)
          {
            char led0 = time_info(temporary>>12 & 0x0F, temporary>>23 & 0x10);   /* store the command value into led variable to display*/

            buffer[index] = led0;
            index++;
          }
          else
          {
            char led0 = time_info(0xFF, temporary>>23 & 0x10);    /* store the command value into led variable to display*/

            buffer[index] = led0;
            index++;
          }
          tuxctl_ldisc_put(tty, buffer, index);
          spin_lock(&lock_tux);   /* get the lock */
          ack = 1;
          spin_unlock(&lock_tux);  /*unlock */
          break;
        }
    }
    return;

}

/******** IMPORTANT NOTE: READ THIS BEFORE IMPLEMENTING THE IOCTLS ************
 *                                                                            *
 * The ioctls should not spend any time waiting for responses to the commands *
 * they send to the controller. The data is sent over the serial line at      *
 * 9600 BAUD. At this rate, a byte takes approximately 1 millisecond to       *
 * transmit; this means that there will be about 9 milliseconds between       *
 * the time you request that the low-level serial driver send the             *
 * 6-byte SET_LEDS packet and the time the 3-byte ACK packet finishes         *
 * arriving. This is far too long a time for a system call to take. The       *
 * ioctls should return immediately with success if their parameters are      *
 * valid.                                                                     *
 *                                                                            *
 ******************************************************************************/

int tuxctl_ioctl(struct tty_struct* tty, struct file* file,
                 unsigned cmd, unsigned long arg) {
    char buffer[10];
    switch (cmd)
    {
        case TUX_INIT:
        {
            int a;
            spin_lock(&lock_tux);
            button_info = 0;
            time_backup = 0;
            spin_unlock(&lock_tux);
            buffer[0] = MTCP_LED_USR;
            buffer[1] = MTCP_BIOC_ON;
            a = tuxctl_ldisc_put(tty, buffer, 2);
            spin_lock(&lock_tux);
            ack = 1;
            spin_unlock(&lock_tux);
            if (a != 0)
            {
              return -EINVAL;
            }

            break;
        }

        case TUX_BUTTONS:
        {
            /* printk 1*/
            int *temp;
            spin_lock(&lock_tux);        /* get the lock */
            temp = (int *)arg;
            copy_to_user(temp, &button_info, sizeof(int));   /*copy to the user-level*/
            spin_unlock(&lock_tux);
            break;
        }

        case TUX_SET_LED:
        {
            int a;
            int index = 0;
            char bitmask;
            unsigned long temp;
            unsigned long temp1;
            spin_lock(&lock_tux);     /*get the lock*/
            time_backup = arg;
            if (ack == 1)
            {
              spin_unlock(&lock_tux);   /* unlcok */
              return -EINVAL;
            }
            spin_unlock(&lock_tux);     /* unlcok */
            temp1 = arg;
            temp = temp1>>16;
            bitmask = temp & 0x0F;
            buffer[0] = MTCP_LED_SET;
            buffer[1] = 0x0F; // always set all the led
            index = 2;
            if (bitmask & 0x08) // set command of leds in order
            {
              char led3 = time_info(temp1 & 0x0F, temp1>>20 & 0x10); /* store the command value into led variable to display*/

              buffer[index] = led3;
              index++;
            }
            else
            {
              char led3 = time_info(0xFF, temp1>>20 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led3;
              index++;
            }
            if (bitmask & 0x04)
            {
              char led2 = time_info(temp1>>4 & 0x0F, temp1>>21 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led2;
              index++;
            }
            else
            {
              char led2 = time_info(0xFF, temp1>>21 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led2;
              index++;
            }
            if (bitmask & 0x02)
            {
              char led1 = time_info(temp1>>8 & 0x0F, temp1>>22 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led1;
              index++;
            }
            else
            {
              char led1 = time_info(0xFF, temp1>>22 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led1;
              index++;
            }
            if (bitmask & 0x01)
            {
              char led0 = time_info(temp1>>12 & 0x0F, temp1>>23 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led0;
              index++;
            }
            else
            {
              char led0 = time_info(0xFF, temp1>>23 & 0x10);  /* store the command value into led variable to display*/

              buffer[index] = led0;
              index++;
            }
            a = tuxctl_ldisc_put(tty, buffer, index);
            spin_lock(&lock_tux);
            ack = 1;
            spin_unlock(&lock_tux);

            if (a != 0)
            {
              return -EINVAL;
            }
            break;
        }

        default:
        {
            return -EINVAL;
        }
    }
    return 0;
}


/*
 * time_info
 *   DESCRIPTION: set the led value into tux
 *   INPUTS: arg: the hexdecimal value we need to display
 *           on: on and off value
 *   OUTPUTS: NONE
 *   RETURN VALUE: command value
 *   SIDE EFFECTS: will show the time on the tux controller
 */
char time_info(unsigned long arg, char on)
{
    char led;
    switch (arg)
    {
      case 0x00:
        led = ZERO;
        led = led | on;
        break;
      case 0x01:
        led = ONE;
        led = led | on;
        break;
      case 0x02:
        led = TWO;
        led = led | on;
        break;
      case 0x03:
        led = THREE;
        led = led | on;
        break;
      case 0x04:
        led = FOUR;
        led = led | on;
        break;
      case 0x05:
        led = FIVE;
        led = led | on;
        break;
      case 0x06:
        led = SIX;
        led = led | on;
        break;
      case 0x07:
        led = SEVEN;
        led = led | on;
        break;
      case 0x08:
        led = EIGHT;
        led = led | on;
        break;
      case 0x09:
        led = NINE;
        led = led | on;
        break;
      case 0x0A:
        led = NUM_A;
        led = led | on;
        break;
      case 0x0B:
        led = NUM_B;
        led = led | on;
        break;
      case 0x0C:
        led = NUM_C;
        led = led | on;
        break;
      case 0x0D:
        led = NUM_D;
        led = led | on;
        break;
      case 0x0E:
        led = NUM_E;
        led = led | on;
        break;
      case 0x0F:
        led = NUM_F;
        led = led | on;
        break;
      default:
        led = 0x00;
    }
    return led;
}
