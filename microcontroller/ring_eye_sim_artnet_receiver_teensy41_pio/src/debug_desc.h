/**
 * @brief
 *
 */

#ifdef DEBUG
#define log(x) Serial.print(x);
#define logln(x) Serial.println(x);
#define loglnHex(x) Serial.println(x, HEX);
#define logHex(x) Serial.print(x, HEX);
#else
#define log(x) ((void)0)
#define logln(x) ((void)0)
#define loglnHex(x) ((void)0)
#define logHex(x) ((void)0)
#endif