;; ABOUTME: Specs for the display width of text in a terminal: wide East Asian
;; ABOUTME: characters take two columns, combining and format characters none.
(local width (require :ezu.cli.width))

(describe "width.of"
          (fn []
            (it "counts one column per narrow character"
                (fn []
                  (assert.are.equal 0 (width.of ""))
                  (assert.are.equal 3 (width.of "abc"))
                  (assert.are.equal 5 (width.of "héllo"))))
            (it "counts two columns for wide characters"
                (fn []
                  (assert.are.equal 6 (width.of "日本語"))
                  (assert.are.equal 2 (width.of "한"))
                  (assert.are.equal 2 (width.of "😀"))
                  (assert.are.equal 4 (width.of "ＡＢ"))))
            (it "counts nothing for combining and format characters"
                (fn []
                  (assert.are.equal 1 (width.of "e\u{301}"))
                  (assert.are.equal 2 (width.of "a\u{200D}b"))
                  (assert.are.equal 2 (width.of "\u{1100}\u{1161}"))))
            (it "counts bytes that aren't UTF-8 as one column each"
                (fn []
                  (assert.are.equal 3 (width.of "a\255b"))))))

(describe "width.of emoji sequences"
          (fn []
            (it "widens a character shown as emoji"
                (fn []
                  (assert.are.equal 2 (width.of "\u{2764}\u{FE0F}"))))
            (it "counts a joined sequence as its first emoji"
                (fn []
                  (assert.are.equal 2
                                    (width.of "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"))))
            (it "counts nothing for a skin tone"
                (fn []
                  (assert.are.equal 2 (width.of "\u{1F44D}\u{1F3FD}"))))
            (it "counts a flag as two columns"
                (fn []
                  (assert.are.equal 2 (width.of "\u{1F1EB}\u{1F1F7}"))))
            (it "counts nothing for the medial and final jamo of Extended-B"
                (fn []
                  (assert.are.equal 2 (width.of "\u{1100}\u{D7B0}"))))))
