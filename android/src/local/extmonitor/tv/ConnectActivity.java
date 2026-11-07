package local.extmonitor.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.*;
import android.content.pm.PackageInfo;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Bundle;
import android.view.*;
import android.widget.*;
import java.util.Locale;

/** Receiver chooser. Video decoding stays in the selected receiver, never in HOME. */
public final class ConnectActivity extends Activity {
    private static final String MOON="com.limelight", OPEN="local.ddmm.opendisplay";
    private LinearLayout content;
    private String route="sunshine";
    private String host="DDMM-MacBook";
    private String hostUUID="";
    private boolean prepared;
    @Override public void onCreate(Bundle state){super.onCreate(state);readIntent(getIntent());show();dispatch(getIntent());}
    @Override public void onNewIntent(Intent i){super.onNewIntent(i);setIntent(i);readIntent(i);show();dispatch(i);}
    @Override public void onResume(){super.onResume();if(prepared)show();}
    private void readIntent(Intent i){
        route=getPreferences(0).getString("route","sunshine");
        String requested=i.getStringExtra("route");
        if("sunshine".equals(requested)||"opendisplay".equals(requested)||"hdmi".equals(requested))route=requested;
        String n=i.getStringExtra("hostname");if(n!=null&&n.matches("[A-Za-z0-9 ._-]{1,80}"))host=n;
        String id=i.getStringExtra("host_uuid");if(id!=null&&id.matches("[a-fA-F0-9-]{36}"))hostUUID=id;
        getPreferences(0).edit().putString("route",route).apply();
    }
    private void dispatch(Intent i){boolean launch=i.getBooleanExtra("launch",false);i.removeExtra("launch");if(launch)content.post(()->launch(route));}
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private TextView text(String value,int size,int color){TextView t=new TextView(this);t.setText(value);t.setTextColor(color);t.setTextSize(size);return t;}
    private GradientDrawable background(int color,int border){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(12));g.setStroke(dp(1),border);return g;}
    private Button action(String label,Runnable run){Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextColor(Color.WHITE);b.setTextSize(15);b.setPadding(dp(18),dp(8),dp(18),dp(8));b.setBackground(background(0xff251e28,0xff554455));b.setOnFocusChangeListener((v,f)->v.setBackground(background(f?0xff4a162b:0xff251e28,f?0xffffc8d4:0xff554455)));b.setOnClickListener(v->run.run());return b;}
    private void show(){
        prepared=true;getWindow().getDecorView().setSystemUiVisibility(5894);
        ScrollView scroll=new ScrollView(this);scroll.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff08080c,0xff24101d}));
        content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(36),dp(20),dp(36),dp(20));scroll.addView(content);setContentView(scroll);
        content.addView(text("eXTMonitor",27,Color.WHITE));
        content.addView(text("SONY XR-75X95EK · "+displayMode(),13,0xffbcafc5));
        LinearLayout cards=new LinearLayout(this);cards.setPadding(0,dp(16),0,dp(16));content.addView(cards);
        String[][] choices={{"sunshine","Sunshine","Moonlight",MOON},{"opendisplay","OpenDisplay","Android Beta · 声音在 Mac",OPEN},{"hdmi","HDMI","需要 HDMI 接线",""}};
        Button focus=null;
        for(String[] c:choices){
            LinearLayout card=new LinearLayout(this);card.setOrientation(1);card.setPadding(dp(13),dp(13),dp(13),dp(13));card.setBackground(background(0xc9211c27,0xff443340));
            LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(0,-2,1);cp.setMargins(dp(4),0,dp(4),0);cards.addView(card,cp);
            card.addView(text(c[1],21,Color.WHITE));card.addView(text(c[2],12,0xffc8baca));card.addView(text(c[3].isEmpty()?"电视输入源":version(c[3]),12,0xffc8baca));
            Button b=action(c[3].isEmpty()?"选择 HDMI 输入":"打开接收端",()->{route=c[0];getPreferences(0).edit().putString("route",route).apply();launch(route);});
            LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(-1,dp(48));bp.topMargin=dp(14);card.addView(b,bp);if(route.equals(c[0]))focus=b;
        }
        LinearLayout row=new LinearLayout(this);content.addView(row);
        for(Button b:new Button[]{action("Moonlight 配对",()->openPackage(MOON)),action("解码能力",this::capabilities),action("返回桌面",()->{startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME));finish();})}){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(46),1);p.setMargins(dp(4),0,dp(4),0);row.addView(b,p);}
        if(focus!=null)focus.requestFocus();
    }
    private String displayMode(){Display.Mode m=getWindowManager().getDefaultDisplay().getMode();return String.format(Locale.US,"%d × %d · %.0f Hz",m.getPhysicalWidth(),m.getPhysicalHeight(),m.getRefreshRate());}
    private String version(String pkg){try{PackageInfo p=getPackageManager().getPackageInfo(pkg,0);return "已安装 · "+p.versionName;}catch(Exception e){return "未安装";}}
    private boolean installed(String pkg){try{getPackageManager().getPackageInfo(pkg,0);return true;}catch(Exception e){return false;}}
    private void openPackage(String pkg){Intent i=getPackageManager().getLeanbackLaunchIntentForPackage(pkg);if(i==null)i=getPackageManager().getLaunchIntentForPackage(pkg);if(i==null){Toast.makeText(this,"接收端未安装",1).show();return;}startActivity(i);}
    private void launch(String selected){
        try{
            if("sunshine".equals(selected)){
                if(!installed(MOON)){openPackage(MOON);return;}
                if(hostUUID.isEmpty()){openPackage(MOON);return;}
                Intent i=new Intent().setComponent(new ComponentName(MOON,"com.limelight.ShortcutTrampoline"));
                i.putExtra("UUID",hostUUID).putExtra("Name",host).putExtra("AppName","Desktop").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
            }else if("opendisplay".equals(selected))openPackage(OPEN);
            else{
                Intent i=new Intent("com.sony.dtv.intent.action.TV_INPUT");
                if(i.resolveActivity(getPackageManager())==null)i=new Intent("android.settings.TV_INPUT_SETTINGS");
                startActivity(i);
            }
        }catch(Exception e){Toast.makeText(this,"接收端未启动，请使用遥控器打开",1).show();}
    }
    private void capabilities(){
        StringBuilder result=new StringBuilder(displayMode()).append("\n\n");
        try{for(MediaCodecInfo codec:new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()){
            if(codec.isEncoder())continue;
            for(String type:codec.getSupportedTypes())if(type.equals("video/hevc")||type.equals("video/avc")){
                try{boolean supported=codec.getCapabilitiesForType(type).getVideoCapabilities().areSizeAndRateSupported(3840,2160,60);result.append(codec.getName()).append("\n").append(type).append(" · 4K60 ").append(supported?"声明支持":"未声明支持").append("\n\n");}catch(Exception ignored){}
            }
        }}catch(Exception e){result.append("解码能力不可读取");}
        result.append("能力声明不代表实际持续帧率。");new AlertDialog.Builder(this).setTitle("显示与解码").setMessage(result).setPositiveButton("关闭",null).show();
    }
}
