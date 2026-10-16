/* Windows x64 launcher. No C runtime, no downloaded runtime.
 * Imports are populated by build_launcher.py after PE linking. */
typedef unsigned short W;
typedef unsigned int DWORD;
typedef void *HANDLE;
#define API __attribute__((ms_abi))
typedef DWORD (API *GetPath)(HANDLE,W*,DWORD);
typedef unsigned int (API *GetDir)(W*,unsigned int);
typedef int (API *CreateProc)(W*,W*,void*,void*,int,DWORD,void*,W*,void*,void*);
typedef int (API *Close)(HANDLE);
typedef void (API *Quit)(unsigned int);
typedef int (API *Message)(HANDLE,W*,W*,unsigned int);
__attribute__((section(".idata"))) unsigned long long imports[256]={1};
typedef struct {DWORD cb; W *reserved,*desktop,*title; DWORD x,y,xsize,ysize,xc,yc,fill,flags; unsigned short show,res2; unsigned char *reserved2; HANDLE in,out,err;} STARTUP;
typedef struct {HANDLE process,thread; DWORD pid,tid;} PROCESS;
static W command[8192], directory[4096], shell[4096];
static int n;
static void add(const char *s){while(*s && n<8190) command[n++]=(unsigned char)*s++; command[n]=0;}
static void wide(W *s){while(*s && n<8190)command[n++]=*s++;command[n]=0;}
void API entry(void){
 DWORD i,len; STARTUP si={0}; PROCESS pi={0};
 len=((GetPath)imports[0])(0,directory,4096);
 if(!len || len>=4095)((Quit)imports[4])(2);
 for(i=len;i>0;i--)if(directory[i-1]=='\\'){directory[i-1]=0;break;}
 if(!i)((Quit)imports[4])(3);
 len=((GetDir)imports[1])(shell,4096);
 if(!len || len>3900)((Quit)imports[4])(4);
 add("\"");wide(shell);add("\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"");
 wide(directory);add("\\app.ps1\"");
 si.cb=sizeof(si);si.flags=1;si.show=0;
 if(!((CreateProc)imports[2])(0,command,0,0,0,0x08000000,0,directory,&si,&pi)){
  static W msg[]={'C','a','n','n','o','t',' ','s','t','a','r','t',' ','W','i','n','d','o','w','s',' ','P','o','w','e','r','S','h','e','l','l','.',0};
  static W title[]={'P','r','e','s','e','t',' ','S','e','e','d',' ','L','a','b',0};
  ((Message)imports[6])(0,msg,title,0x10);((Quit)imports[4])(1);
 }
 ((Close)imports[3])(pi.thread);((Close)imports[3])(pi.process);((Quit)imports[4])(0);
}
