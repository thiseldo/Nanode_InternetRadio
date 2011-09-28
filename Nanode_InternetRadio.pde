/**
 * Nanode and VS1053B MP3 Shield Internet radio player
 * The example uses DHCP to determine the local IP address, gateway,
 * and DNS server.
 * 
 * The LCD display used is a I2C connected 20x4 display.
 * Details available at http://john.crouchley.com/blog/archives/612
 *
 * Tuning is achieved by connecting a 100k (could be 10k) potentiometer between +5v,
 * GND and A0. This is selects one of 8 pre-defined stations.
 *
 * Written By and (c) Andrew D Lindsay, Sep 2011
 * http://blog.thiseldo.co.uk
 * Feel free to use this code, modify and redistribute.
 * 
 * Sample headers received from url.
 * HTTP/1.0 200 OK
 * Content-Type: audio/mpeg
 * icy-br:48
 * ice-audio-info: ice-samplerate=32000;ice-bitrate=48;ice-channels=1
 * icy-br:48
 * icy-description:Heart Berkshire
 * icy-genre:Pop
 * icy-name:Heart Berkshire
 * icy-private:0
 * icy-pub:1
 * icy-url:http://media-ice.musicradio.com/HeartBerkshireMP3Low
 * Server: Icecast 2.3.2
 * Cache-Control: no-cache
 * 
 * 
 * TODO: (In no particular order)
 * 1. Buffering
 * 2. Connection loss/reconnect
 * 3. Station selection
 */

// If using a Nanode (www.nanode.eu) instead of Arduino and ENC28J60 EtherShield then
// use this define:
#define NANODE
#define USE_LCD
#undef USE_SRAM
#undef DEBUG

#include <SPI.h>
#include <EtherShield.h>
#include <vs1053mp3.h>
#ifdef NANODE
#include <NanodeMAC.h>
#endif

#ifdef USE_LCD
#include <Wire.h>
#endif

#ifdef USE_SRAM
#include <SRAM9.h>
#endif

// Please modify the following lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
// how did I get the mac addr? Translate the first 3 numbers into ascii is: TUX
#ifdef NANODE
static uint8_t mymac[6] = { 
  0,0,0,0,0,0 };
#else
static uint8_t mymac[6] = { 
  0x54,0x55,0x58,0x12,0x34,0x56 };
#endif

// IP and netmask allocated by DHCP
static uint8_t myip[4] = { 
  0,0,0,0 };
static uint8_t mynetmask[4] = { 
  0,0,0,0 };

// IP address of the host being queried to contact (IP of the first portion of the URL):
static uint8_t websrvip[4] = { 
  192,168,1,2 };

// Default gateway, dns server and dhcp server. 
// These are found using DHCP
static uint8_t gwip[4] = { 
  0,0,0,0 };
static uint8_t dnsip[4] = { 
  0,0,0,0 };
static uint8_t dhcpsvrip[4] = { 
  0,0,0,0 };


//============================================================================================================
//Define some stations. media-ice.musicradio.com has a few examples
// Visiting the url with a browser will list the urls, pick one with MP3Low at the end
// as these seem to work best.
#define HOSTNAME "media-ice.musicradio.com"      

PROGMEM prog_char station0[] = "/HeartBerkshireMP3Low";
PROGMEM prog_char station1[] = "/CapitalMP3Low";
PROGMEM prog_char station2[] = "/CapitalSouthCoastMP3Low";
PROGMEM prog_char station3[] = "/ChillMP3Low";
PROGMEM prog_char station4[] = "/ClassicFMMP3Low";
PROGMEM prog_char station5[] = "/GoldMP3Low";
PROGMEM prog_char station6[] = "/LBC973MP3Low";
PROGMEM prog_char station7[] = "/XFMMP3Low";

PROGMEM prog_char *stationList[]  = {
  station0, station1, station2, station3, station4, station5, station6, station7 };
  
boolean startDownload = false;

EtherShield es=EtherShield();
#ifdef NANODE
NanodeMAC mac( mymac );
#endif

vs1053mp3 mp3 = vs1053mp3();

char stationDesc[50];
char stationGenre[20];
char stationName[50];

#define BUFFER_SIZE 750
static uint8_t buf[BUFFER_SIZE+1];

int startPlayback = 1;

#define TUNING_PIN A0

int currentStationId = 0;

// Statuscode values
// 0 = 200/OK data is for us
// 1 = Could be data
// 4 = Not our request
void browserresult_callback(uint8_t statuscode,uint16_t datapos, uint16_t dlen ){
  char headerEnd[4] = {
    '\r','\n','\r','\n'      };
  long contentLen = 0L;

#ifdef DEBUG
  Serial.print("\nIn callback, statuscode: "); 
  Serial.print(statuscode,DEC);
  Serial.print( " DataPos: " );
  Serial.print( datapos, DEC );
  Serial.print( " DataLen: " );
  Serial.println( dlen, DEC );
#endif

  // Scan headers looking for Content-Length: 5
  // Start of a line, look for "Content-Length: "
  // now search for the csv data - it follows the first blank line
  uint16_t pos = datapos;
  if( statuscode == 0 ) {    // && startPlayback > 0 ) {
#ifdef DEBUG
    Serial.println((char*)&buf[pos]);
#endif

    while (pos < (dlen+datapos))    // loop until end of buffer (or we break out having found what we wanted)
    {
      // Look for line with \r\n on its own
      if( strncmp ((char*)&buf[pos],headerEnd, 4) == 0 ) {
#ifdef DEBUG
        Serial.println("End of headers");
#endif
        pos += 4;
        return;
        // break;
      }
      if( strncmp ((char*)&buf[pos], "icy-description:", 16) == 0 ) {
        // Station Description
        pos += 16;          // Skip to value
        char ch = buf[pos++];
        uint8_t slen = 0;
        while( ch != '\n' && ch != '\r' && slen < 49) {
          stationDesc[slen++] = ch;
          ch = buf[pos++];
        }
        stationDesc[slen] = '\0';
      } 
      else if( strncmp ((char*)&buf[pos], "icy-genre:", 10) == 0 ) {
        // Genre
        pos += 10;          // Skip to value
        char ch = buf[pos++];
        uint8_t slen = 0;
        while( ch != '\n' && ch != '\r' && slen < 19) {
          stationGenre[slen++] = ch;
          ch = buf[pos++];
        }
        stationGenre[slen] = '\0';
      } 
      else if( strncmp ((char*)&buf[pos], "icy-name:", 9) == 0 ) {
        // Station Description
        pos += 9;          // Skip to value
        char ch = buf[pos++];
        uint8_t slen = 0;
        while( ch != '\n' && ch != '\r' && slen < 49) {
          stationName[slen++] = ch;
          ch = buf[pos++];
        }
        stationName[slen] = '\0';
#ifdef USE_LCD
        displayStation( true );
#endif
//        startPlayback--;
      }  
      else if( strncmp ((char*)&buf[pos], "Content-Length:", 15) == 0 ) {
        // Found Content-Length 
        pos += 16;          // Skip to value
        char ch = buf[pos++];
        contentLen = 0;
        while(ch >= '0' && ch <= '9' ) {  // Only digits
          contentLen *= 10;
          contentLen += (ch - '0');
          ch = buf[pos++];
        }
      }
      pos++;
    }
    return;
  }

  int payloadLen = dlen;  // - pos;

  if( statuscode == 1 && payloadLen > 0 ) {
    // Play buffer
    mp3.playBuffer( &buf[datapos], payloadLen );
  }
}

void displayMessageP( int row, int col, const prog_char *str, boolean clearRow ) {
#ifdef USE_LCD
  if( clearRow && col == 1) {
    setCursor( row, col );
    sendStrP( PSTR("                    ") );
  }
  setCursor( row, col );
  sendStrP( str);
#endif
}


void displayMessage( int row, int col, char *str, boolean clearRow ) {
#ifdef USE_LCD
  if( clearRow && col == 1) {
    setCursor( row, col );
    sendStrP( PSTR("                    ") );
  }
  setCursor( row, col );
  sendStr( str);
#endif
}

void displayStation( boolean hasStation ) {
  displayMessage( 2, 1, hasStation ? stationName : (char*)"Connecting...", true );
  displayMessage( 3, 1, hasStation ? stationGenre : (char*)" ", true );
}

int getStation() {
    // read the value from the sensor:
  int analogValue = analogRead( TUNING_PIN );

  return analogValue / 128;
}


void setup(){
#ifdef DEBUG
  Serial.begin(19200);
  Serial.println("Nanode MP3 Test");
#endif
#ifdef USE_LCD
  Wire.begin(); // join i2c bus (address optional for master)
  sendReset();
  delay(200);
  cursorOff();
  clearLCD();
  delay(100);
  displayMessageP( 1, 1,  PSTR("Nanode Radio v0.2"), false);
  displayMessageP( 2, 1,  PSTR("Initialising..."), false );
  displayMessageP( 4, 1,  PSTR("blog.thiseldo.co.uk"), false );
#endif

  // Initialise SPI interface
  es.ES_enc28j60SpiInit();

  mp3.init();

  currentStationId = getStation();

  // initialize enc28j60
#ifdef NANODE
  es.ES_enc28j60Init(mymac,8);
#else
  es.ES_enc28j60Init(mymac);
#endif

#ifdef DEBUG
  Serial.print( "ENC28J60 version " );
  Serial.println( es.ES_enc28j60Revision(), HEX);
  if( es.ES_enc28j60Revision() <= 0 ) {
    Serial.println( "Failed to access ENC28J60");
    while(1);    // Just loop here
  }
#endif

  es.ES_client_set_wwwip(websrvip);  // target web server

#ifdef DEBUG
  Serial.println("Ready");
#endif

}

#ifdef DEBUG
// Output a ip address from buffer from startByte
void printIP( uint8_t *buf ) {
  for( int i = 0; i < 4; i++ ) {
    Serial.print( buf[i], DEC );
    if( i<3 )
      Serial.print( "." );
  }
}
#endif
void printHex( uint8_t hexval ) {
  if( hexval < 16 ) {
    Serial.print("0");
  }
  Serial.print( hexval, HEX );
  Serial.print( " " );
}

void loop()
{
  static uint32_t timetosend;
  uint16_t dat_p;
  int sec = 0;
  long lastDnsRequest = 0L;
  int plen = 0;
  long lastDhcpRequest = millis();
  uint8_t dhcpState = 0;
  boolean gotIp = false;
  //  boolean startDownload = false;

  // Get IP Address details
  if( es.allocateIPAddress(buf, BUFFER_SIZE, mymac, 80, myip, mynetmask, gwip, dnsip, dhcpsvrip ) > 0 ) {
#ifdef DEBUG
    // Display the results:
    Serial.print( "My IP: " );
    printIP( myip );
    Serial.println();

    Serial.print( "Netmask: " );
    printIP( mynetmask );
    Serial.println();

    Serial.print( "DNS IP: " );
    printIP( dnsip );
    Serial.println();

    Serial.print( "GW IP: " );
    printIP( gwip );
    Serial.println();
    Serial.println("Look up hostname");
    displayMessageP( 2, 1,  PSTR("Got IP Address..."), true );
#endif    
    // Perform DNS Lookup for host name
    if( es.resolveHostname(buf, BUFFER_SIZE,(uint8_t*)HOSTNAME ) > 0 ) {
#ifdef DEBUG
      Serial.println("Hostname resolved");
#endif    
      displayMessageP( 2, 1,  PSTR("Got hostname..."), true );
    } 
    else {
#ifdef DEBUG
      Serial.println("Failed to resolve hostname");
#endif
      displayMessageP( 2, 1,  PSTR("DNS Failed"), true );
    }
  } 
  else {
    // Failed, do something else....
    displayMessageP( 2, 1,  PSTR("DHCP Failed"), true );
#ifdef DEBUG
    Serial.println("Failed to get IP Address");
#endif    
  }

  // Main processing loop now we have our addresses
  while( es.ES_dhcp_state() == DHCP_STATE_OK ) {
    // Stays within this loop as long as DHCP state is ok
    // If it changes then it drops out and forces a renewal of details
    // handle ping and wait for a tcp packet - calling this routine powers the sending and receiving of data
    plen = es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf);
    dat_p=es.ES_packetloop_icmp_tcp(buf,plen);
    if( plen > 0 ) {
      // We have a packet
      // Check if IP data
      if (dat_p == 0) {
        if (es.ES_client_waiting_gw() ){
          // No ARP received for gateway
          continue;
        }
      } 
    }
    // If we have IP address for server and its time then request data

    if( startPlayback > 0 )  //&& (millis() - timetosend > 3000) )  // every 10 seconds
    {
      timetosend = millis();
      //     startDownload = true;
#ifdef DEBUG
      Serial.println("Sending request");
#endif
      displayStation(false);
      startPlayback = 0;
      // note the use of PSTR - this puts the string into code space and is compulsory in this call
      // second parameter is a variable string to append to HTTPPATH, this string is NOT a PSTR
      es.ES_client_browse_url((char*)pgm_read_word(&(stationList[currentStationId])), NULL, PSTR(HOSTNAME), &browserresult_callback);
    } else {
      int newStation = getStation();
      if(newStation != currentStationId ) {
        mp3.closeStream();
        currentStationId = newStation;
        startPlayback = 1;
      }  
    }
  }
}

#ifdef USE_LCD
void sendStr(char* b)
{
  Wire.beginTransmission(0x12); // transmit to device 12
  while (*b)
  {
    if (*b == 0xfe || *b == 0xff) Wire.send(0xfe);
    Wire.send(*b++); // sends one byte
  }
  Wire.endTransmission(); // stop transmitting
  delay(2);
}
void sendStrP(const prog_char* b)
{
  Wire.beginTransmission(0x12); // transmit to device 12

  char c;
  while ((c = pgm_read_byte(b++))) {
    if (c == 0xfe || c == 0xff) Wire.send(0xfe);
    Wire.send(c); // sends one byte
  }
  Wire.endTransmission(); // stop transmitting
  delay(2);
}

void clearLCD()
{
  Wire.beginTransmission(0x12); // transmit to device 12
  Wire.send(0xfe); // signal command follows
  Wire.send(0x01); // send the command
  Wire.endTransmission(); // stop transmitting
  delay(2);
}

void cursorOff()
{
  Wire.beginTransmission(0x12); // transmit to device 12
  Wire.send(0xfe); // signal command follows
  Wire.send(0x0C); // send the command
  Wire.endTransmission(); // stop transmitting
  delay(2);
}

void sendReset()
{
  Wire.beginTransmission(0x12); // transmit to device 12
  Wire.send(0xff); // signal command follows
  Wire.send(0xf1); // send the reset
  Wire.endTransmission(); // stop transmitting
  delay(4);
  // the address is now changed and you need to use the new address
}

void setHome()
{
  Wire.beginTransmission(0x12); // transmit to device 12
  Wire.send(0xfe); // signal command follows
  Wire.send(0x80); // send the command
  Wire.endTransmission(); // stop transmitting
  delay(2);
}

void setCursor(byte row, byte column )
{
  byte temp = (column - 1);  //get column byte
  switch ( row )  //get row byte
  {
    //line 1 is already set up
  case 2:
    temp += 0x40;
    break;
  case 3:
    temp += 0x14;
    break;
  case 4:
    temp += 0x54;
    break;
  default:
    break;
  }

  Wire.beginTransmission(0x12); // transmit to device 12
  Wire.send(0xfe); // signal command follows
  Wire.send(0x80 + temp ); // send the command
  Wire.endTransmission(); // stop transmitting
  delay(2);
}
#endif


