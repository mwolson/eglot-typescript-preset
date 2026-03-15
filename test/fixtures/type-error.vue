<!-- TS type error below won't surface until full tsserver proxying is
     implemented in rass-preset.tpl.py (currently responds with null,
     which gives "simple project" mode: template errors only). -->
<script lang="ts">
const x: number = "bad";
</script>
<template>
  <p>hello</p>
</template>
