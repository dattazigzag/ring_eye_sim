// =============================================================
// ScreenGrabber — transparent, draggable + RESIZABLE "lens" + Robot grab
// =============================================================
// Extension A (screen-capture input source). A live input ALTERNATIVE to
// video: an undecorated, always-on-top, per-pixel-transparent JFrame the user
// drags over any desktop region; java.awt.Robot grabs what shows through it
// (inset past the 2px border) into a PImage. MediaHandler feeds that frame into
// the SAME pipeline as video (raw grab -> the ring sampler does the reduction),
// and updateProcessedImage() scales the grab to the 480 canvas — so the lens may
// be ANY size and the ring still samples a 480 image. Smaller lens = upscaled
// (softer); bigger = downsampled. Sampling geometry is unaffected by lens size.
//
// Interaction:
//   - DRAG the body  -> move the lens (move cursor)
//   - DRAG a corner  -> resize, locked 1:1, the OPPOSITE corner stays fixed
//                       (a diagonal resize cursor shows on corner hover)
//   - a small "W x H" readout sits in a strip BELOW the captured square so it's
//     never captured (the grab region is the inset square above it). Default
//     480 x 480; min 96; max ~ the screen's shorter side.
//
// Undecorated windows have NO native resize handles, so resize is done by
// hit-testing the corners in the mouse listener and calling setBounds(). The
// capture square = the cyan-bordered region; the info strip hangs below it.
//
// Pure AWT/Swing — coexists with the P3D main sketch; grab() runs on the
// Processing animation thread (from MediaHandler.update()); mouse + setBounds
// run on the EDT. capSize is a plain int (atomic read/write) so the two threads
// need no locking — a one-frame-stale grab mid-drag is benign.
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
import java.awt.Font;
import java.awt.Cursor;
import java.awt.Toolkit;
import java.awt.Dimension;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.BasicStroke;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import javax.swing.JFrame;
import javax.swing.JPanel;

class ScreenGrabber {
  static final int DEFAULT_SIZE = 480;   // default lens edge — matches a 480 canvas
  static final int MIN_SIZE     = 96;    // smallest capture square
  static final int BORDER       = 2;     // cyan frame thickness
  static final int INSET        = 4;     // skip the border when capturing
  static final int CORNER       = 18;    // corner grab-zone (px) for resize
  static final int INFO_H       = 20;    // info strip height below the square

  PApplet parent;
  Robot   robot;
  JFrame  lens   = null;
  JPanel  panel  = null;
  int[]   capBuf = null;           // reused getRGB() target
  PImage  out    = null;           // reused output image (re-created on size change)

  // Live capture-square edge (logical px). Written on the EDT during a resize
  // drag, read by grab() on the animation thread — int access is atomic, so no
  // lock; a one-frame-stale value during a drag is harmless.
  int capSize = DEFAULT_SIZE;
  int maxSize = DEFAULT_SIZE;      // computed from the screen at start()

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

    // Cap the max to the (primary) screen with a margin; clamp the default in
    // case of a very small display. Reset to default each time the lens opens
    // (screen mode is session-only — size isn't persisted).
    Dimension scr = Toolkit.getDefaultToolkit().getScreenSize();
    maxSize = max(MIN_SIZE, min(scr.width, scr.height) - 80);
    capSize = min(DEFAULT_SIZE, maxSize);

    lens = new JFrame();
    lens.setUndecorated(true);                     // required before translucency
    lens.setSize(capSize, capSize + INFO_H);       // square capture + info strip below
    lens.setLocation(300, 300);
    lens.setAlwaysOnTop(true);
    lens.setBackground(new Color(0, 0, 0, 0));     // per-pixel transparent interior

    panel = new JPanel() {
      protected void paintComponent(Graphics g) {
        Graphics2D g2 = (Graphics2D) g;
        g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
          RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        // Cyan frame around the CAPTURE SQUARE only (the top capSize x capSize).
        g2.setColor(new Color(57, 184, 213));      // same cyan as the main marker
        g2.setStroke(new BasicStroke(BORDER));
        g2.drawRect(1, 1, capSize - 3, capSize - 3);

        // "W x H" readout in the strip BELOW the square — never captured (the
        // grab region is the inset square above). Faint pill for legibility.
        String label = capSize + " x " + capSize;
        g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
        int tw    = g2.getFontMetrics().stringWidth(label);
        int pad   = 6;
        int pillW = tw + pad * 2;
        int pillH = INFO_H - 4;
        int pillX = (capSize - pillW) / 2;
        int pillY = capSize + 2;
        g2.setColor(new Color(0, 0, 0, 150));
        g2.fillRoundRect(pillX, pillY, pillW, pillH, 8, 8);
        g2.setColor(new Color(57, 184, 213));
        g2.drawString(label, pillX + pad, pillY + pillH - 4);
      }
    };
    panel.setOpaque(false);
    lens.setContentPane(panel);

    LensMouse lm = new LensMouse();
    panel.addMouseListener(lm);
    panel.addMouseMotionListener(lm);

    lens.setVisible(true);
    log("[screen] lens shown (" + capSize + "x" + capSize
      + ") — drag body to move, drag a corner to resize (1:1)");
  }

  void stop() {
    if (lens != null) {
      lens.dispose();
      lens  = null;
      panel = null;
      log("[screen] lens disposed");
    }
  }

  // -------------------------------------------------------------
  // Mouse — corner hit -> resize (1:1, opposite corner fixed); else move.
  // Uses Math.* (not PApplet min/max/abs) to stay safe inside this doubly-nested
  // inner class. mousePressed always re-decides the mode, so a drag can't start
  // with a stale one.
  // -------------------------------------------------------------
  class LensMouse extends java.awt.event.MouseAdapter {
    Point   off;                 // move: cursor offset within the window
    boolean resizing = false;
    int     corner;              // 0=TL 1=TR 2=BL 3=BR
    Point   anchor;              // screen pos of the FIXED (opposite) corner

    // Which corner of the capture square is (x,y) in? -1 = none (move zone).
    int cornerAt(int x, int y) {
      if (y > capSize) return -1;                  // info strip -> move, not a corner
      boolean l = x <= CORNER, r = x >= capSize - CORNER;
      boolean t = y <= CORNER, b = y >= capSize - CORNER;
      if (t && l) return 0;
      if (t && r) return 1;
      if (b && l) return 2;
      if (b && r) return 3;
      return -1;
    }

    public void mouseMoved(java.awt.event.MouseEvent e) {
      int cur;
      switch (cornerAt(e.getX(), e.getY())) {
        case 0:  cur = Cursor.NW_RESIZE_CURSOR; break;
        case 1:  cur = Cursor.NE_RESIZE_CURSOR; break;
        case 2:  cur = Cursor.SW_RESIZE_CURSOR; break;
        case 3:  cur = Cursor.SE_RESIZE_CURSOR; break;
        default: cur = Cursor.MOVE_CURSOR;      break;
      }
      panel.setCursor(Cursor.getPredefinedCursor(cur));
    }

    public void mousePressed(java.awt.event.MouseEvent e) {
      int c = cornerAt(e.getX(), e.getY());
      if (c >= 0) {
        resizing = true;
        corner   = c;
        Rectangle b = lens.getBounds();            // window bounds (screen coords)
        int ed = b.width;                          // == capSize (square edge)
        // Fixed corner = the OPPOSITE of the dragged one, in screen coords. The
        // capture square's top-left == the window origin (b.x, b.y).
        switch (corner) {
          case 0: anchor = new Point(b.x + ed, b.y + ed); break;  // drag TL -> fix BR
          case 1: anchor = new Point(b.x,      b.y + ed); break;  // drag TR -> fix BL
          case 2: anchor = new Point(b.x + ed, b.y);      break;  // drag BL -> fix TR
          case 3: anchor = new Point(b.x,      b.y);      break;  // drag BR -> fix TL
        }
      } else {
        resizing = false;
        off = e.getPoint();
      }
    }

    public void mouseDragged(java.awt.event.MouseEvent e) {
      if (resizing) {
        int mx = e.getXOnScreen(), my = e.getYOnScreen();
        int edge = Math.max(Math.abs(mx - anchor.x), Math.abs(my - anchor.y));
        edge = Math.max(MIN_SIZE, Math.min(edge, maxSize));      // clamp, 1:1
        int nx, ny;
        switch (corner) {
          case 0:  nx = anchor.x - edge; ny = anchor.y - edge; break;  // fix BR
          case 1:  nx = anchor.x;        ny = anchor.y - edge; break;  // fix BL
          case 2:  nx = anchor.x - edge; ny = anchor.y;        break;  // fix TR
          default: nx = anchor.x;        ny = anchor.y;        break;  // fix TL
        }
        capSize = edge;
        lens.setBounds(nx, ny, edge, edge + INFO_H);
        panel.repaint();
      } else {
        Point p = lens.getLocation();
        lens.setLocation(p.x + e.getX() - off.x, p.y + e.getY() - off.y);
      }
    }

    public void mouseReleased(java.awt.event.MouseEvent e) {
      resizing = false;
    }
  }

  // Grab the desktop behind the capture square (inset past the border) into a
  // PImage at the captured (physical) size — 2x on Retina, which the downstream
  // resize handles. Uses the live capSize (atomic int). Returns null if not
  // showing / no Robot / not yet realized.
  PImage grab() {
    if (robot == null || lens == null || !lens.isShowing()) return null;
    Point loc;
    try {
      loc = lens.getLocationOnScreen();            // == capture-square top-left
    }
    catch (Exception e) {
      return null;                                 // window not realized yet
    }
    int side = capSize - 2*INSET;                  // snapshot capSize once
    if (side <= 0) return null;
    Rectangle region = new Rectangle(loc.x + INSET, loc.y + INSET, side, side);
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
