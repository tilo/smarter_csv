
when testing `parse` methods:

* SmarterCSV.default_options are not loaded when testing `parse` methods by themselves
  
* make sure to always pass all options to the 'parse' methods, incl. acceleration

* always wrap tests, so that both accelerated and un-accelerated code-paths are run
