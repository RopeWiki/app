var span = document.querySelectorAll('.ContextDetails');
for (var i = span.length; i--;) {
  (function () {
    var t;
    span[i].onmouseover = function () {
      for (var j = span.length; j--;) {
        span[j].className = 'ContextDetails'; 
      }
      clearTimeout(t);
      this.className = 'ContextDetailsHover';
    };
    span[i].onmouseout = function () {
      var self = this;
      t = setTimeout(function () {
          self.className = 'ContextDetails';
      }, 300);
    };
  })();
}