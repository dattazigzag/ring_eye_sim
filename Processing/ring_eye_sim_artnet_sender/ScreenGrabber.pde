// =============================================================
// ScreenGrabber — transparent draggable 480x480 "lens" + Robot grab
// =============================================================
// Extension A (screen-capture input source). A live input ALTERNATIVE to
// video: an undecorated, always-on-top, per-pixel-transparent JFrame the user
// drags over any desktop region; java.awt.Robot grabs what shows through it
// (inset past the 2px border) into a PImage. MediaHandler feeds that frame into
// the SAME pipeline as video (raw grab -> the ring sampler does the reduction).
//
// Pure AWT/Swing — coexists with the P3D main sketch; grab() runs on the
// Processing animation thread (called from MediaHandler.update()).
//
// macOS: needs Screen Recording permission (System Settings > Privacy &
// Security > Screen Recording) for Processing / the exported app — grant once,
// then RESTART the app. See contexts/99_gotchas.md.
// =============================================================

// Specific imports only — a wildcard `import java.awt.*` pulls in java.awt.Button
// and java.awt.Canvas, which collide with ControlP5's Button (modeButton) and
// the sketch's own Canvas class ("type is ambiguous"). See contexts/99_gotchas.md.
import java.awt.Robot;
import java.awt.Rectangle;
import java.awt.Point;
import java.awt.Color;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.BasicStroke;
import java.awt.image.BufferedImage;
import javax.swing.JFrame;
import javax.swing.JPanel;

class ScreenGrabber {
  static final int SIZE   = 480;   // lens size — matches a 480 canvas
  static final int BORDER = 2;     // cyan frame thickness
  static final int INSET  = 4;     // skip the border when capturing

  PApplet parent;
  Robot   robot;
  JFrame  lens   = null;
  int[]   capBuf = null;           // reused getRGB() target
  PImage  out    = null;           // reused output image (re-created on size change)

  ScreenGrabber(PApplet parent) {
    this.parent = parent;
    try {
      robot = new Robot();
    }
    catch (Exception e) {
      log("[screen] Robot init failed: " + e.getMessage());
      robot = null;
    }
  }

  boolean isActive() {
    return lens != null && lens.isShowing();
  }

  void start() {
    if (lens != null) return;                      // already up
    lens = new JFrame();
    lens.setUndecorated(true);                     // required before translucency
    lens.setSize(SIZE, SIZE);
    lens.setLocation(300, 300);
    lens.setAlwaysOnTop(true);
    lens.setBackground(new Color(0, 0, 0, 0));     // per-pixel transparent interior

    JPanel panel = new JPanel() {
      protected void paintComponent(Graphics g) {
        Graphics2D g2 = (Graphics2D) g;
        g2.setColor(new Color(57, 184, 213));      // same cyan as the main marker
        g2.setStroke(new BasicStroke(BORDER));
        g2.drawRect(1, 1, getWidth() - 3, getHeight() - 3);
      }
    };
    panel.setOpaque(false);
    lens.setContentPane(panel);

    java.awt.event.MouseAdapter ma = new java.awt.event.MouseAdapter() {
      Point off;
      public void mousePressed(java.awt.event.MouseEvent e) {
        off = e.getPoint();
      }
      public void mouseDragged(java.awt.event.MouseEvent e) {
        Point p = lens.getLocation();
        lens.setLocation(p.x + e.getX() - off.x, p.y + e.getY() - off.y);
      }
    };
    panel.addMouseListener(ma);
    panel.addMouseMotionListener(ma);

    lens.setVisible(true);
    log("[screen] lens shown — drag it over the content to capture");
  }

  void stop() {
    if (lens != null) {
      lens.dispose();
      lens = null;
      log("[screen] lens disposed");
    }
  }

  // Grab the desktop behind the lens (inset past the border) into a PImage at
  // the captured (physical) size — 2x on Retina, which the downstream resize
  // handles. Returns null if not showing / no Robot / not yet on-screen.
  PImage grab() {
    if (robot == null || lens == null || !lens.isShowing()) return null;
    Point loc;
    try {
      loc = lens.getLocationOnScreen();
    }
    catch (Exception e) {
      return null;                                 // window not realized yet
    }
    Rectangle region = new Rectangle(loc.x + INSET, loc.y + INSET, SIZE - 2*INSET, SIZE - 2*INSET);
    BufferedImage shot = robot.createScreenCapture(region);
    int w = shot.getWidth(), h = shot.getHeight();
    if (w <= 0 || h <= 0) return null;
    if (capBuf == null || capBuf.length != w*h) capBuf = new int[w*h];
    shot.getRGB(0, 0, w, h, capBuf, 0, w);
    if (out == null || out.width != w || out.height != h) out = createImage(w, h, RGB);
    out.loadPixels();
    System.arraycopy(capBuf, 0, out.pixels, 0, w*h);
    out.updatePixels();
    return out;
  }
}
