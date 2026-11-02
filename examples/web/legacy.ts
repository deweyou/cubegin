import type {AsyncEngine} from '../../sdk/web/dist/worker-client.js';

export function initializeLegacy(engine:AsyncEngine):void {
  const container=document.querySelector<HTMLDetailsElement>('#legacy')!;
  const input=container.querySelector<HTMLInputElement>('#algorithm')!;
  const status=container.querySelector<HTMLElement>('#status')!;
  const error=container.querySelector<HTMLElement>('#error')!;
  let current='';
  let initialized=false;
  async function busy(action:()=>Promise<void>) {
    container.querySelectorAll('button').forEach(button=>button.disabled=true);
    error.textContent='';
    try {await action();} catch(failure) {error.textContent=String(failure);}
    finally {container.querySelectorAll('button').forEach(button=>button.disabled=false);}
  }
  async function apply() {
    const snapshot=await engine.evaluate(input.value);
    current=snapshot.facelets;
    container.querySelector('#diagram')!.innerHTML=snapshot.svg;
    container.querySelector('#state')!.textContent=snapshot.facelets;
    status.textContent=snapshot.solved?'Solved':'Scrambled';
  }
  container.addEventListener('toggle',()=>{
    if(container.open&&!initialized){initialized=true;void busy(apply);}
  });
  container.querySelector('form')!.onsubmit=event=>{event.preventDefault();void busy(apply);};
  container.querySelector('#scramble')!.addEventListener('click',()=>void busy(async()=>{input.value=(await engine.scramble(42)).algorithm;await apply();}));
  container.querySelector('#solve')!.addEventListener('click',()=>void busy(async()=>{input.value=`${input.value} ${await engine.solve(current)}`.trim();await apply();}));
}
